//+------------------------------------------------------------------+
//|                                                                  |
//| Gérer une stratégie en s'appuyant sur les données                |
//| communes                                                         |
//| (Le code est compatible MT4 et MT5)                              |
//|                                                                  |
//| - Détection d'une opportunité                                    |
//| - Affectation avec un ticket ouvert                              |
//| - Gestion des positions avec les détections                      |
//|                                                                  |
//+------------------------------------------------------------------+
//| Liste  des fonctions : (A compléter avec IA)


//////////////////////////////////////////////////////////
//                                                      //
//              C O N S T A N T E S                     //
//                                                      //
//////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////
//                                                      //
//                 I N C L U D E S                      //
//                                                      //
//////////////////////////////////////////////////////////
#include <OPR_Bot/Datas.mqh>

//////////////////////////////////////////////////////////
//                                                      //
//                  C L A S S                           //
//                                                      //
//////////////////////////////////////////////////////////
class CStrategy
{
//==================================
//--- PRIVATE
//==================================    
private:
    // Données de la stratégie
    //------------------------
    CDatas        DATAS;
  
    // Données des indicateurs et ORB
    //--------------------------------
    int     m_HandleSMA20;    // Handle SMA20
    int     m_HandleSMA50;    // Handle SMA50
    int     m_HandleATR;      // Handle ATR (filtre range ORB)

    // ✅ VARIABLES POUR VERROUILLAGE JOURNALIER
    //-------------------------------------------
    int             m_LockedDay;           // Jour verrouillé
    bool            m_PositionOpened;      // Flag position ouverte
    
    // Données
    //--------
    ENUM_TIMEFRAMES m_Period;
    bool            m_InitOk;

    // Fonctions
    //----------
    double   FindStop(const STRUCT_STRATEGY &i_datas);
    bool     CheckSMA(ENUM_TREND &i_trend);
    void     ApplyBreakEven(const MqlTick &i_tick);
    bool     IsPositionOpenedToday(const MqlTick &i_tick);
    bool     HasPositionForSymbol(void);
    bool     HasPendingOrderForSymbol(void);

//==================================
//--- PUBLIC
//==================================    
public:
    // Fonctions
    //----------
    bool   Config(const string            i_strategy_name,
                  const ENUM_TIMEFRAMES   i_period,
                  const string            i_folder);

    bool   ConfigOk(void) { return(m_InitOk);  }

    void    End(void);

    // Infos venants de l'extérieur
    //-----------------------------
    void    SetTicket(const int i_detection, const int i_Ticket)     { DATAS.SetTicket(i_detection, i_Ticket); }

    // Gestion des données
    //--------------------
    int    GetPositionNb(void)                                      { return(DATAS.GetPositionNb()); }

    void    DeleteDetection(void)                                    { DATAS.DeleteDetection(); }

    void    CloseOfPositions(void)                                   { DATAS.CloseOfPositions(); }

    void    Detection(void);

    void    ManagePositions(void);                                   
};

//+------------------------------------------------------------------+
//| Config                                                           |
//| Initialise l'objet avec la création des indicateurs              |
//| INPUT:                                                           |
//|  Nom de la stratégie                                             |
//|  Période de la stratégie                                         |                                                                 
//| OUTPUT:                                                          |
//|  None                                                            |
//+------------------------------------------------------------------+
bool CStrategy::Config(const string            i_strategy_name,
                       const ENUM_TIMEFRAMES   i_period,
                       const string            i_folder)
{
    // Initialisation (également des indicateurs)
    //---------------    
    m_InitOk = false;
    m_Period = i_period;    

    // ✅ INITIALISER LE VERROUILLAGE
    //--------------------------------
    m_LockedDay = -1;
    m_PositionOpened = false;    
    
    // Configure la classe pour les données
    //-------------------------------------
    if (!DATAS.Config(i_strategy_name, i_period, i_folder)) return(false);

    // TODO : Initialisation des spécificités de la stratégie
    //-------------------------------------------------------

    // Initialisation
    //---------------
    m_HandleSMA20  = INVALID_HANDLE;
    m_HandleSMA50  = INVALID_HANDLE;
    m_HandleATR    = INVALID_HANDLE;      

    // Création des handles pour les indicateurs

    // SMA20 et SMA50 (M5)
    //--------------------
    m_HandleSMA20  = iMA(Symbol(), PERIOD_H1, K_CStrat_SMA_Short, 0, MODE_SMA, PRICE_CLOSE);
    if (m_HandleSMA20 == INVALID_HANDLE)
    {
        LOG.ERROR(DATAS.GetStrategyName() + "Impossible d'initialiser l'indicateur SMA20 !!!", __FUNCTION__);
        return(false);
    }
    m_HandleSMA50  = iMA(Symbol(), PERIOD_H1, K_CStrat_SMA_Long, 0, MODE_SMA, PRICE_CLOSE);
    if (m_HandleSMA50 == INVALID_HANDLE)
    {
        LOG.ERROR(DATAS.GetStrategyName() + "Impossible d'initialiser l'indicateur SMA50 !!!", __FUNCTION__);
        return(false);
    }
    
    // ATR sur K_ORB_TF — filtre de range minimum
   //---------------------------------------------
   m_HandleATR = iATR(Symbol(), K_ORB_TF, 14);
   if (m_HandleATR == INVALID_HANDLE)
   {
       LOG.ERROR(DATAS.GetStrategyName() + "Impossible d'initialiser l'indicateur ATR !!!", __FUNCTION__);
       return(false);
   }
    
    // Fin de l'initialisation
    //------------------------
    m_InitOk = true;
    LOG.INFO(DATAS.GetStrategyName() + "Stratégie OPR initialisée", __FUNCTION__);
    return(true);
}

//+------------------------------------------------------------------+
//| End                                                              |
//| Ferme l'objet                                                    |
//| INPUT:                                                           |
//|  None                                                            |
//| OUTPUT:                                                          |
//|  None                                                            |
//+------------------------------------------------------------------+
void CStrategy::End(void)
{ 
    // Gère les données de la stratégie
    //---------------------------------
    DATAS.End(); 

    // TODO : Terminaison des spécificités de la stratégie
    //----------------------------------------------------

    if (m_HandleSMA20 != INVALID_HANDLE) IndicatorRelease(m_HandleSMA20);
    if (m_HandleSMA50 != INVALID_HANDLE) IndicatorRelease(m_HandleSMA50);
    if (m_HandleATR   != INVALID_HANDLE) IndicatorRelease(m_HandleATR);
}

//+--------------------------------------------------------------------+
//| Detection                                                          |
//| Analyse la stratégie en cas de nouvelle bougie                     |
//| INPUT:                                                             |
//|  None                                                              |
//| OUTPUT:                                                            |    
//|  None                                                              |
//+--------------------------------------------------------------------+
void CStrategy::Detection(void)
{ 
    // Variables locales
    //------------------
    STRUCT_STRATEGY          l_Datas;
    int                      l_NoDetection;
    bool                     l_DetectionOk;
    MqlTick                  l_TickData;
    string                   l_Header;
    
    // Initialise le traitement
    //-------------------------
    l_NoDetection = 0;
    l_DetectionOk = false;
    ZeroMemory(l_Datas);

    // Lit les dernières données du marché    
    //------------------------------------
    if (!SymbolInfoTick(Symbol(), l_TickData)) 
    {
        LOG.WARNING(DATAS.GetStrategyName() + "Lecture des données récentes du marché impossible", __FUNCTION__);
        return;
    }

    // Données et valeurs statiques pour qu'elles ne changent pas à chaque tick
    //-------------------------------------------------------------------------
    static datetime opr_start     = 0;
    static datetime opr_session   = 0;
    static datetime opr_end       = 0;
    static datetime opr_close     = 0;
    static datetime safe_read_time = 0;
    static double   opr_high      = 0.0;
    static double   opr_low       = 0.0;
    static int      opr_day       = -1;   
    MqlDateTime     dt;
    TimeCurrent(dt);    
    
    // On ne rentre ici qu'une seule fois par jour, à minuit (ou au premier tick du jour)
    //-----------------------------------------------------------------------------------
    if (dt.day != opr_day)
    {
        // Reset journalier
        //-----------------
        opr_high = 0.0;
        opr_low  = 0.0;
        opr_day  = dt.day;

        // Récupère les heures OPR dynamiques selon marché + DST
        //-------------------------------------------------------
        string today_str = TimeToString(TimeCurrent(), TIME_DATE);
        opr_start      = StringToTime(today_str + " 16:30");
        safe_read_time = opr_start + PeriodSeconds(K_ORB_TF);
        opr_session    = StringToTime(today_str + " 16:45");
        opr_end        = StringToTime(today_str + " 18:30");
        opr_close      = StringToTime(today_str + " 22:00");

        LOG.INFO("Nouvelle journée : OPR Start=" + TimeToString(opr_start) +
                 " | Session=" + TimeToString(opr_session) +
                 " | End="     + TimeToString(opr_end) +
                 " | Close="   + TimeToString(opr_close), __FUNCTION__);
    }       

    // ✅ VÉRIFICATION : Une position est-elle ouverte aujourd'hui ?
    //-------------------------------------------------------------
    if (IsPositionOpenedToday(l_TickData))
    {
        return;
    }

    // ✅ VÉRIFICATION ZONE NEWS
    //-------------------------
    if (!PARAM.OutsideSecurityZone())
    {
        if (HasPendingOrderForSymbol())
        {
           LOG.INFO("🔴 Zone NEWS - Annulation des ordres en attente", __FUNCTION__);
           DATAS.CancelPendingOrder();
        }
        return;
    }
        
    // Clôture forcée à OPR_Close
    //---------------------------
    if (TimeCurrent() >= opr_close)
    {
        if (PositionsTotal() > 0)
        {
            LOG.INFO("Clôture forcée des positions : OPR_Close", __FUNCTION__);
            DATAS.CloseOfPositions();            
        }
        DATAS.CancelPendingOrder();
        return;
    }

    // Logique de récupération de l'OPR high et low
    //----------------------------------------------
    if (TimeCurrent() >= safe_read_time)
    {
        if (opr_high == 0.0 || opr_low == 0.0)
        {
            double high_buf[], low_buf[];
            
            if (CopyHigh(Symbol(), K_ORB_TF, opr_start, 1, high_buf) == 1) 
            {
                opr_high = high_buf[0];
                LOG.INFO("OPR High enregistré: " + DoubleToString(opr_high, _Digits), __FUNCTION__);
            }
            else
            {
                LOG.WARNING("Impossible de lire OPR High", __FUNCTION__);
                return;
            }
            
            if (CopyLow(Symbol(), K_ORB_TF, opr_start, 1, low_buf) == 1) 
            {
                opr_low = low_buf[0];
                LOG.INFO("OPR Low enregistré: " + DoubleToString(opr_low, _Digits), __FUNCTION__);
            }
            else
            {
                LOG.WARNING("Impossible de lire OPR Low", __FUNCTION__);
                return;
            }                        
        }
    }
    else
    {
        return;  // Trop tôt
    }

    // Annulation des ordres non exécutés après OPR_End
    //--------------------------------------------------
    if (TimeCurrent() >= opr_end)
    {
        if (OrdersTotal() > 0)
        {
            LOG.INFO("OPR - End dépassé - Annulation ordres en attente", __FUNCTION__);
            DATAS.CancelPendingOrder();
        }
        return;
    }
/*    
   // Filtre ATR — range ORB trop petite
   //------------------------------------
   if (K_MinRange_ATR_Ratio > 0.0)
   {
       double atr_buf[];
       if (CopyBuffer(m_HandleATR, 0, 1, 1, atr_buf) == 1)
       {
           double range = opr_high - opr_low;
           double atr   = atr_buf[0];
           if (range < K_MinRange_ATR_Ratio * atr)
           {
               LOG.INFO("Range ORB trop petite (" + DoubleToString(range, _Digits) +
                        ") vs ATR×ratio ("        + DoubleToString(K_MinRange_ATR_Ratio * atr, _Digits) +
                        ") - Session ignorée", __FUNCTION__);
               return;
           }
       }
       else
       {
           LOG.WARNING("ATR indisponible - filtre range ignoré", __FUNCTION__);
       }
   }
*/
    // === ANALYSE INDICATEURS ===
    //----------------------------
    ENUM_TREND ema_trend = eT_Unknown;
    
    if (!CheckSMA(ema_trend)) return;

    // SI ORDRE EN ATTENTE, VÉRIFIER VALIDITÉ
    //----------------------------------------
    if (HasPendingOrderForSymbol())
    {
        if (st_trend != ema_trend)
        {
            LOG.INFO("Divergence ST/EMA - Annulation ordre", __FUNCTION__);
            DATAS.CancelPendingOrder();
        }
        return;
    }

    // Analyse OPR (seulement si pas de trade en cours)
    //-------------------------------------------------
    if (HasPositionForSymbol()) return; 

    // Convergence obligatoire ST + EMA
    //---------------------------------
    if (st_trend != ema_trend) return;

    // Offset anti fausse cassure (issu de la config actif)
    //------------------------------------------------------
    double offset = K_Offset;
    double rr = K_TP_Override;

    //--------------------
    // Contrôle si achat
    //--------------------
    if ((st_trend == eT_Bull) && (TimeCurrent() >= opr_session) && (TimeCurrent() < opr_end))
    {
        if (l_TickData.ask > opr_high + offset)
        {
            // Prix a déjà cassé → vérification slippage
            double l_Slippage = (l_TickData.ask - (opr_high + offset));
            if ((K_MaxSlippage_Points > 0.0) && (l_Slippage > K_MaxSlippage_Points))
            {
                LOG.INFO("🚫 Cassure trop lointaine (" + DoubleToString(l_Slippage, 0) +
                         " pts) > max autorisé (" + DoubleToString(K_MaxSlippage_Points, 0) +
                         " pts) - abandon", __FUNCTION__);
                return;
            }
            // Slippage acceptable → bascule ordre au marché
            l_NoDetection = DATAS.GetNewDetection();
            DATAS.GetData(l_NoDetection, l_Datas);
            l_Datas.Trend         = eT_Bull;
            l_Datas.Entry         = l_TickData.ask;
            l_Datas.StopLoss      = this.FindStop(l_Datas);
            l_Datas.TakeProfit    = l_Datas.Entry + rr * (l_Datas.Entry - l_Datas.StopLoss);
            l_Datas.IsMarketOrder = true;
            l_DetectionOk         = true;
            LOG.WARNING("🚀 [INSTANT BREAKOUT] Bascule ordre au MARCHÉ | Slippage : " +
                        DoubleToString(l_Slippage, 0) + " pts", __FUNCTION__);
        }
        else
        {
            // Prix pas encore cassé → ordre stop classique
            l_NoDetection = DATAS.GetNewDetection();
            DATAS.GetData(l_NoDetection, l_Datas);
            l_Datas.Trend         = eT_Bull;
            l_Datas.Entry         = opr_high + offset;
            l_Datas.StopLoss      = this.FindStop(l_Datas);
            l_Datas.TakeProfit    = l_Datas.Entry + rr * (l_Datas.Entry - l_Datas.StopLoss);
            l_Datas.IsMarketOrder = false;
            l_DetectionOk         = true;
            LOG.INFO("Ordre BUY STOP placé", __FUNCTION__);
        }
    }

    //--------------------
    // Contrôle si vente
    //--------------------    
    else if ((st_trend == eT_Bear) && (TimeCurrent() >= opr_session) && (TimeCurrent() < opr_end))
    {
        if (l_TickData.bid < opr_low - offset)
        {
            // Prix a déjà cassé → vérification slippage
            double l_Slippage = ((opr_low - offset) - l_TickData.bid);
            if ((K_MaxSlippage_Points > 0.0) && (l_Slippage > K_MaxSlippage_Points))
            {
                LOG.INFO("🚫 Cassure trop lointaine (" + DoubleToString(l_Slippage, 0) +
                         " pts) > max autorisé (" + DoubleToString(K_MaxSlippage_Points, 0) +
                         " pts) - abandon", __FUNCTION__);
                return;
            }
            // Slippage acceptable → bascule ordre au marché
            l_NoDetection = DATAS.GetNewDetection();
            DATAS.GetData(l_NoDetection, l_Datas);
            l_Datas.Trend         = eT_Bear;
            l_Datas.Entry         = l_TickData.bid;
            l_Datas.StopLoss      = this.FindStop(l_Datas);
            l_Datas.TakeProfit    = l_Datas.Entry - rr * (-l_Datas.Entry + l_Datas.StopLoss);
            l_Datas.IsMarketOrder = true;
            l_DetectionOk         = true;
            LOG.WARNING("🚀 [INSTANT BREAKOUT] Bascule ordre au MARCHÉ | Slippage : " +
                        DoubleToString(l_Slippage, 0) + " pts", __FUNCTION__);
        }
        else
        {
            // Prix pas encore cassé → ordre stop classique
            l_NoDetection = DATAS.GetNewDetection();
            DATAS.GetData(l_NoDetection, l_Datas);
            l_Datas.Trend         = eT_Bear;
            l_Datas.Entry         = opr_low - offset;
            l_Datas.StopLoss      = this.FindStop(l_Datas);
            l_Datas.TakeProfit    = l_Datas.Entry - rr * (-l_Datas.Entry + l_Datas.StopLoss);
            l_Datas.IsMarketOrder = false;
            l_DetectionOk         = true;
            LOG.INFO("Ordre SELL STOP placé", __FUNCTION__);
        }
    }

    // Gère les paramètres de la détection
    //--------------------------------------
    if (l_DetectionOk)
    {        
        l_Datas.Size = MONEY.CalculateLotSize(l_Datas);

        if (l_Datas.Size <= 0.0)
        {
            LOG.WARNING("Taille de lot invalide", __FUNCTION__);
            return;
        }

        l_Header = LOG.InfosLogOperation(DATAS.GetStrategyName(), l_Datas.No_detection, Symbol());
        LOG.INFO(l_Header +
                 " : Opportunité " + TrendToString(l_Datas.Trend) +
                 " : Taille = "    + DoubleToString(l_Datas.Size,       MONEY.GetDigitLot()) +
                 " , Entry = "     + DoubleToString(l_Datas.Entry,      Digits()) +
                 " , SL = "        + DoubleToString(l_Datas.StopLoss,   Digits()) +
                 " , TP = "        + DoubleToString(l_Datas.TakeProfit, Digits()), __FUNCTION__);

        DATAS.SetData(l_NoDetection, l_Datas);

        // Invalidation de dernière minute
        //--------------------------------
        if (st_trend != ema_trend)
        {
            LOG.INFO(" Invalidation immédiate - ST != EMA", __FUNCTION__);
            return;
        }
        BROKER.SendOrder(DATAS.GetStrategyName(), l_Datas);
    }    
}

//+------------------------------------------------------------------+
//| ManagePositions                                                  |
//| Appelée à chaque tick depuis OnTick()                            |
//| Gère dans l'ordre :                                              |
//|  1. Zone NEWS  → annulation immédiate des ordres en attente      |
//|  2. BreakEven  → déplacement du SL si ratio atteint              |
//|  3. Divergence ST/EMA → annulation si conditions invalides       |
//| INPUT:                                                           |
//|  None                                                            |
//| OUTPUT:                                                          |
//|  None                                                            |
//+------------------------------------------------------------------+
void CStrategy::ManagePositions(void)
{
    // Variables locales
    //------------------
    MqlTick              l_Tick;
    ENUM_TREND           l_StTrend   = eT_Unknown;
    ENUM_TREND           l_EmaTrend  = eT_Unknown;

    // Lecture du tick courant
    //------------------------
    if (!SymbolInfoTick(Symbol(), l_Tick))
    {
        LOG.WARNING("ManagePositions : Impossible de lire le tick", __FUNCTION__);
        return;
    }
    
    // 1. ZONE NEWS : Priorité absolue
    //--------------------------------
    if (!PARAM.OutsideSecurityZone())
    {
        if (HasPendingOrderForSymbol())
        {
            LOG.INFO("🔴 Zone NEWS (tick) - Annulation immédiate des ordres", __FUNCTION__);
            DATAS.CancelPendingOrder();
        }

        // BE actif même en zone NEWS pour protéger les positions ouvertes
        //-----------------------------------------------------------------
        if (K_Apply_BE)
        {
            ApplyBreakEven(l_Tick);
        }
        return;
    }

    // 2. BREAKEVEN
    //-------------
    if (K_Apply_BE)
    {
        ApplyBreakEven(l_Tick);
    }

    // 3. DIVERGENCE ST/EMA
    //---------------------
    if (HasPendingOrderForSymbol())
    {
        if (!CheckSuperTrend(l_StTrend) || !CheckEMA(l_EmaTrend) || (l_StTrend != l_EmaTrend))
        {
            LOG.INFO("⚡ Divergence ST/EMA (tick) - Annulation ordre", __FUNCTION__);
            DATAS.CancelPendingOrder();
        }
    }
}

//////////////////////////////////////////////////////////
//                                                      //
//                P R I V A T E                         //
//                                                      //
//////////////////////////////////////////////////////////

//+------------------------------------------------------------------+
//| IsPositionOpenedToday                                            |
//| Détecte si une position est ouverte, verrouille si oui           |
//| INPUT:                                                           |
//|  i_tick : tick courant                                           |
//| OUTPUT:                                                          |
//|  TRUE si position déjà ouverte aujourd'hui                       |
//+------------------------------------------------------------------+
bool CStrategy::IsPositionOpenedToday(const MqlTick &i_tick)
{
    MqlDateTime dt;
    TimeCurrent(dt);
    datetime day_start;
    int      l_Deals;
    
    // Reset à minuit
    //---------------
    if (dt.day != m_LockedDay)
    {
        m_LockedDay      = dt.day;
        m_PositionOpened = false;
        LOG.INFO("✅ Nouveau jour - Verrouillage réinitialisé", __FUNCTION__);
    }
    
    if (m_PositionOpened) return(true);
    
    // Détection via historique du jour
    //---------------------------------
    day_start = StringToTime(TimeToString(TimeCurrent(), TIME_DATE) + " 00:00");
    
    if (!HistorySelect(day_start, TimeCurrent())) return(false);
    l_Deals = HistoryDealsTotal();
    for(int i = l_Deals - 1; i >= 0; i--)
    {
        ulong l_Ticket = HistoryDealGetTicket(i);

        if (HistoryDealGetString(l_Ticket, DEAL_SYMBOL)                != Symbol())              continue;
        if (HistoryDealGetInteger(l_Ticket, DEAL_MAGIC)                != (K_Magic + I_Robot_ID)) continue;
        if (HistoryDealGetInteger(l_Ticket, DEAL_ENTRY)                != DEAL_ENTRY_IN)          continue;

        LOG.INFO("🔒 Position ouverte trouvée dans l'historique d'aujourd'hui", __FUNCTION__);
        m_PositionOpened = true;
        return(true);
    }

    // Détection via cassure du niveau d'entrée d'un ordre en attente
    //----------------------------------------------------------------
    for (int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong l_Ticket = OrderGetTicket(i);

        if (OrderGetString(ORDER_SYMBOL)  != Symbol())              continue;
        if (OrderGetInteger(ORDER_MAGIC)  != (K_Magic + I_Robot_ID)) continue;

        double entry = OrderGetDouble(ORDER_PRICE_OPEN);
        long   type  = OrderGetInteger(ORDER_TYPE);

        if (type == ORDER_TYPE_BUY_STOP  && i_tick.ask >= entry)
        {
            LOG.INFO("🔒 Cassure OPR détectée — verrouillage journée (BUY)", __FUNCTION__);
            m_PositionOpened = true;
            return(true);
        }
        if (type == ORDER_TYPE_SELL_STOP && i_tick.bid <= entry)
        {
            LOG.INFO("🔒 Cassure OPR détectée — verrouillage journée (SELL)", __FUNCTION__);
            m_PositionOpened = true;
            return(true);
        }    
    }

    // Détection via positions ouvertes actuellement
    //-----------------------------------------------
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong l_Ticket = PositionGetTicket(i);

        if (PositionGetString(POSITION_SYMBOL)  != Symbol())              continue;
        if (PositionGetInteger(POSITION_MAGIC)  != (K_Magic + I_Robot_ID)) continue;

        LOG.INFO("🔒 Position détectée (ouverte actuellement)", __FUNCTION__);
        m_PositionOpened = true;
        return(true);
    }
    
    return(false);
}

//+------------------------------------------------------------------+
//| HasPositionForSymbol                                             |
//| Détecte si une position est ouverte pour l'actif                 |
//| INPUT:                                                           |
//|  None                                                            |
//| OUTPUT:                                                          |
//|  TRUE si une position est ouverte                                |
//+------------------------------------------------------------------+
bool CStrategy::HasPositionForSymbol(void)
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong l_Ticket = PositionGetTicket(i);
        if (PositionGetString(POSITION_SYMBOL)  != Symbol())              continue;
        if (PositionGetInteger(POSITION_MAGIC)  != (K_Magic + I_Robot_ID)) continue;
        return(true);
    }
    return(false);
}

//+------------------------------------------------------------------+
//| HasPendingOrderForSymbol                                         |
//| Détecte si un ordre est en attente pour l'actif                  |
//| INPUT:                                                           |
//|  None                                                            |
//| OUTPUT:                                                          |
//|  TRUE si un ordre est en attente                                 |
//+------------------------------------------------------------------+
bool CStrategy::HasPendingOrderForSymbol(void)
{
    for (int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong l_Ticket = OrderGetTicket(i);
        if (OrderGetString(ORDER_SYMBOL)  != Symbol())              continue;
        if (OrderGetInteger(ORDER_MAGIC)  != (K_Magic + I_Robot_ID)) continue;
        return(true);
    }
    return(false);
}

//+------------------------------------------------------------------+
//| FindStop                                                         |
//| Calcule le stop loss (milieu du range OPR)                       |
//| INPUT:                                                           |
//|  i_datas : données de la détection                               |
//| OUTPUT:                                                          |
//|  Prix du stop loss (milieu du range OPR)                         |
//+------------------------------------------------------------------+
double CStrategy::FindStop(const STRUCT_STRATEGY &i_datas)
{
    static datetime opr_start      = 0;
    static datetime safe_read_time = 0;
    static double   opr_high       = 0.0;
    static double   opr_low        = 0.0;
    static int      opr_day        = -1;

    MqlDateTime dt;
    TimeCurrent(dt);

    if (dt.day != opr_day)
    {
        opr_high = 0.0;
        opr_low  = 0.0;
        opr_day  = dt.day;

        // Récupère uniquement start_h/m (FindStop n'a besoin que de opr_start)
        //-----------------------------------------------------------------------
        string today_str = TimeToString(TimeCurrent(), TIME_DATE);
        opr_start        = StringToTime(today_str + " 16:30");
        safe_read_time   = opr_start + PeriodSeconds(K_ORB_TF);

        LOG.INFO("FindStop | OPR Start=" + TimeToString(opr_start), __FUNCTION__);
    }

    if (TimeCurrent() >= safe_read_time)
    {
        if (opr_high == 0.0 || opr_low == 0.0)
        {
            double high_buf[], low_buf[];

            if (CopyHigh(Symbol(), K_ORB_TF, opr_start, 1, high_buf) == 1) 
            {
                opr_high = high_buf[0];
                LOG.INFO("OPR High enregistré: " + DoubleToString(opr_high, _Digits), __FUNCTION__);
            }
            else
            {
                LOG.WARNING("Impossible de lire OPR High", __FUNCTION__);
            }
            
            if (CopyLow(Symbol(), K_ORB_TF, opr_start, 1, low_buf) == 1) 
            {
                opr_low = low_buf[0];
                LOG.INFO("OPR Low enregistré: " + DoubleToString(opr_low, _Digits), __FUNCTION__);
            }
            else
            {
                LOG.WARNING("Impossible de lire OPR Low", __FUNCTION__);
            }                        
        }
    }

    // Retourne le milieu de range comme stop loss
    //---------------------------------------------
    double range = opr_high - opr_low;

   if (i_datas.Trend == eT_Bull)
   {
       switch(K_SL_Type)
       {
           case eSL_Mid:           return((opr_high + opr_low) / 2.0);
           case eSL_LowHigh:       return(opr_low);
           case eSL_LowHighBuffer: return(opr_low - range * K_SL_Buffer_Ratio);
       }
   }
   else
   {
       switch(K_SL_Type)
       {
           case eSL_Mid:           return((opr_high + opr_low) / 2.0);
           case eSL_LowHigh:       return(opr_high);
           case eSL_LowHighBuffer: return(opr_high + range * K_SL_Buffer_Ratio);
       }
   }
   return((opr_high + opr_low) / 2.0); // fallback
}

//+------------------------------------------------------------------+
//| CheckEMA                                                         |
//| Vérifie SMA20 vs SMA50 (bougie clôturée)                         |
//| INPUT:                                                           |
//|  i_trend : tendance détectée (par référence)                     |
//| OUTPUT:                                                          |
//|  TRUE si on a une tendance sur les SMAs                          |
//+------------------------------------------------------------------+
bool CStrategy::CheckSMA(ENUM_TREND &i_trend)
{
    double sma20[];
    double sma50[];

    if (CopyBuffer(m_HandleSMA20, 0, 1, 1, sma20) != 1)
    {
        LOG.WARNING(DATAS.GetStrategyName() + "SMA20 indisponible", __FUNCTION__);
        return(false);
    }    
    if (CopyBuffer(m_HandleSMA50, 0, 1, 1, sma50) != 1)
    {
        LOG.WARNING(DATAS.GetStrategyName() + "SMA50 indisponible", __FUNCTION__);
        return(false);
    }    
    ArraySetAsSeries(sma20, true);
    ArraySetAsSeries(sma50, true);

    if      (sma20[0] > sma50[0]) i_trend = eT_Bull;
    else if (sma20[0] < sma50[0]) i_trend = eT_Bear;
    else                          return(false);

    return(true);
}

//+------------------------------------------------------------------+
//| ApplyBreakEven                                                   |
//| Déplace le SL au niveau du prix d'entrée + buffer                |
//| dès que le ratio cible est atteint                               |
//| INPUT:                                                           |
//|  i_tick : tick courant (pour le spread)                          |
//| OUTPUT:                                                          |
//|  None                                                            |
//+------------------------------------------------------------------+
void CStrategy::ApplyBreakEven(const MqlTick &i_tick)
{
    // Variables locales
    //------------------
    MqlTradeRequest      l_Request;
    MqlTradeResult       l_Result;
    ulong    l_Ticket;
    ulong    l_Magic;
    string   l_Symbol;
    double   l_OpenPrice;
    double   l_CurrentSL;
    double   l_CurrentTP;
    double   l_CurrentPrice;
    double   l_CurrentProfit;
    double   l_Ratio;
    double   l_InitialRisk;
    double   l_NewSL;
    double   l_Point;
    double   l_Spread;
    double   l_Buffer;
    bool     l_Update;
    long     l_Type;
    int      l_Digits;     

    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        l_Ticket = PositionGetTicket(i);
        l_Symbol = PositionGetString(POSITION_SYMBOL);
        
        if (l_Symbol != Symbol())                                          continue;
        if (PositionGetInteger(POSITION_MAGIC) != (K_Magic + I_Robot_ID)) continue;

        l_OpenPrice    = PositionGetDouble(POSITION_PRICE_OPEN);
        l_CurrentSL    = PositionGetDouble(POSITION_SL);
        l_CurrentTP    = PositionGetDouble(POSITION_TP);
        l_CurrentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
        l_Type         = PositionGetInteger(POSITION_TYPE);
        l_Magic        = PositionGetInteger(POSITION_MAGIC);
        l_Digits       = (int)SymbolInfoInteger(l_Symbol, SYMBOL_DIGITS);
        l_Point        = SymbolInfoDouble(l_Symbol, SYMBOL_POINT);
        
        // ✅ FIX BE INFINI : SL déjà au-delà du prix d'entrée → BE déjà appliqué
        //------------------------------------------------------------------------
        if (l_Type == POSITION_TYPE_BUY  && l_CurrentSL >= l_OpenPrice)           continue;
        if (l_Type == POSITION_TYPE_SELL && l_CurrentSL <= l_OpenPrice
                                         && l_CurrentSL >  0.0)                   continue;

        l_InitialRisk = MathAbs(l_OpenPrice - l_CurrentSL);
        if (l_InitialRisk == 0) continue;

        if (l_Type == POSITION_TYPE_BUY)
            l_CurrentProfit = l_CurrentPrice - l_OpenPrice;
        else
            l_CurrentProfit = l_OpenPrice - l_CurrentPrice;
        
        l_Ratio = l_CurrentProfit / l_InitialRisk;

        // Ratio cible non atteint → pas encore de BE
        //--------------------------------------------
        double be_ratio = K_BE_Override;
        if (l_Ratio < be_ratio) continue;
        
        l_Update = false;
        l_Spread = i_tick.ask - i_tick.bid;
        l_Buffer = K_BE_Buffer * l_Point;
                    
        if (l_Type == POSITION_TYPE_BUY)
        {
            l_NewSL = l_OpenPrice + l_Spread + l_Buffer;
            if (l_CurrentSL < l_NewSL) l_Update = true;
        }
        else
        {
            l_NewSL = l_OpenPrice - l_Spread - l_Buffer;
            if (l_CurrentSL > l_NewSL) l_Update = true;
        }
         
        LOG.INFO("🔍 BE check | " + l_Symbol +
                 " | Ratio : "     + DoubleToString(l_Ratio,      2) + "R" +
                 " | Spread : "    + DoubleToString(l_Spread,      l_Digits) +
                 " | Buffer : "    + DoubleToString(l_Buffer,      l_Digits) +
                 " | NewSL : "     + DoubleToString(l_NewSL,       l_Digits) +
                 " | CurrentSL : " + DoubleToString(l_CurrentSL,   l_Digits) +
                 " | Update : "    + (l_Update ? "OUI" : "NON"), __FUNCTION__);         

        if (!l_Update) continue;
        
        // Éviter race condition, ordre BE arrive après TP durant une news volatile
        //-------------------------------------------------------------------------
        if (!PositionSelectByTicket(l_Ticket))
        {
            LOG.INFO("✅ Position #" + IntegerToString(l_Ticket) +
                     " déjà fermée (TP/SL atteint) - BE ignoré", __FUNCTION__);
            continue;
        }        

        ZeroMemory(l_Request);
        ZeroMemory(l_Result);

        l_Request.action   = TRADE_ACTION_SLTP;
        l_Request.position = l_Ticket;
        l_Request.symbol   = l_Symbol;
        l_Request.sl       = NormalizeDouble(l_NewSL, l_Digits);
        l_Request.tp       = l_CurrentTP;
        l_Request.magic    = l_Magic;

        ResetLastError();
        if (!OrderSend(l_Request, l_Result))
        {
            LOG.ERROR("OrderSend BE échec : " + ErrorToString(GetLastError()), __FUNCTION__);
        }
        else
        {
            if (l_Result.retcode == TRADE_RETCODE_DONE         ||
                l_Result.retcode == TRADE_RETCODE_PLACED        ||
                l_Result.retcode == TRADE_RETCODE_DONE_PARTIAL)
            {
                LOG.INFO("✅ BE appliqué #" + IntegerToString(l_Ticket) +
                         " | Ratio : "       + DoubleToString(l_Ratio,  2) + "R" +
                         " | Nouveau SL : "  + DoubleToString(l_NewSL,  l_Digits), __FUNCTION__);
            }
            else
            {
                LOG.WARNING("⚠️ BE refusé #"  + IntegerToString(l_Ticket) +
                            " | Retcode : "   + IntegerToString(l_Result.retcode) +
                            " | "             + l_Result.comment, __FUNCTION__);
            }
        }
    }
}