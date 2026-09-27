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
#include <BB_ADX_EXPERT/Datas.mqh>

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
    int     m_HandleEMA20_M5;    // Handle EMA20 directionnelle
    int     m_HandleEMA50_M5;    // Handle EMA50 directionnelle
    int     m_HandleEMA20_M1;    // Handle EMA20 de management
    int     m_HandleEMA50_M1;    // Handle EMA50 de management
    int     m_HandleST_D;        // Handle SuperTrend directionnelle
    int     m_HandleST_M;        // Handle SuperTrend M1 pour détection plateaux
    int     m_HandleATR;         // Handle ATR (filtre range ORB)

    // ✅ SUPERTREND M1 - DÉTECTION DES PLATEAUX
    //-------------------------------------------
    STRUCT_ST_HISTORY m_STPlateau;               // État du tracking structurel (1 obs / M1)
    datetime          m_LastProcessedM1Bar;      // Anti-doublon : dernière bougie M1 traitée
    ulong             m_STTrackedPositionTicket; // Ticket de la position suivie (anti-confusion)

    // ✅ PENDING SL — exécution indépendante de la détection (CORR2, CORR13)
    // Une modif de SL décidée à un plateau peut être retentée à chaque tick
    // tant qu'elle n'a pas abouti, sans recalculer la structure.
    //----------------------------------------------------------------------
    bool              m_PendingSLMove;           // Une modif de SL est-elle en attente ?
    double            m_PendingSL;               // Prix cible du SL en attente
    int               m_PendingSLLevel;          // Niveau entier du plateau cible (log)
    double            m_PendingSLFirstValue;     // first_value du plateau cible (log)

    // ✅ ANTI-DOUBLE-TENTATIVE (CORR3) : flag par tick.
    //    Si UpdateSTPlateauDetection() a déjà tenté TryMoveSLToPlateauLevel()
    //    sur ce tick, RetryPendingSLMove() ne fait rien — le retry commencera
    //    au tick suivant. Remis à false en début de ManagePositions().
    //----------------------------------------------------------------------
    bool              m_SLAttemptedThisTick;

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
    bool     CheckSuperTrend(ENUM_TREND &i_trend);
    bool     CheckEMA(ENUM_TREND &i_trend);
    void     ApplyBreakEven(const MqlTick &i_tick);
    bool     CheckTrendExitOnM1(void);
    bool     ClosePositionByTicket(const ulong i_ticket, const ENUM_POSITION_TYPE i_position_type);
    
    // ✅ SUPERTREND M1 - DÉTECTION DES PLATEAUX
    //-------------------------------------------
    void     InitSTPlateauTracking(const ENUM_TREND i_expected_direction, const ulong i_position_ticket);
    void     UpdateSTPlateauDetection(const MqlTick &i_tick);
    void     ResetSTPlateauTracking(void);
    bool     TryMoveSLToPlateauLevel(const double i_target_sl,
                                     const int    i_target_level,
                                     const double i_target_first_val);
    double   NormalizeToTickSize(const double i_price);

    // ✅ PENDING SL — exécution indépendante de la détection (CORR2, CORR13)
    //----------------------------------------------------------------------
    void     RetryPendingSLMove(void);
    void     ClearPendingSLMove(void);
    bool     IsMoreFavorableSL(const double i_candidate, const double i_reference,
                               const ENUM_POSITION_TYPE i_type);

    // ✅ POSITION LIFECYCLE — ticket-based reset (CORR3, CORR4)
    //----------------------------------------------------------
    bool     IsOurPositionTicket(const ulong i_ticket);
    ulong    FindOurPositionTicket(void);
    void     EnsureTrackingMatchesPosition(void);
    
    bool     IsSessionValid(void);
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
    m_HandleEMA20_M5  = INVALID_HANDLE;
    m_HandleEMA50_M5  = INVALID_HANDLE;
    m_HandleEMA20_M1  = INVALID_HANDLE;
    m_HandleEMA50_M1  = INVALID_HANDLE;
    m_HandleST_D      = INVALID_HANDLE; 
    m_HandleST_M      = INVALID_HANDLE;
    m_HandleATR       = INVALID_HANDLE;
    
    // ✅ SUPERTREND M1 INITIALIZATION
    //--------------------------------
    m_LastProcessedM1Bar      = 0;
    m_STTrackedPositionTicket = 0;
    m_PendingSLMove           = false;
    m_PendingSL               = 0.0;
    m_PendingSLLevel          = 0;
    m_PendingSLFirstValue     = 0.0;
    m_SLAttemptedThisTick     = false;
    ZeroMemory(m_STPlateau);
    m_STPlateau.active        = false;      

    // Création des handles pour les indicateurs

    // EMA20 et EMA50 (M5)
    //--------------------
    m_HandleEMA20_M5  = iMA(Symbol(), PERIOD_M5, 20, 0, MODE_EMA, PRICE_CLOSE);
    if (m_HandleEMA20_M5 == INVALID_HANDLE)
    {
        LOG.ERROR(DATAS.GetStrategyName() + "Impossible d'initialiser l'indicateur EMA20 directionnelle !!!", __FUNCTION__);
        return(false);
    }
    m_HandleEMA50_M5 = iMA(Symbol(), PERIOD_M5, 50, 0, MODE_EMA, PRICE_CLOSE);
    if (m_HandleEMA50_M5 == INVALID_HANDLE)
    {
        LOG.ERROR(DATAS.GetStrategyName() + "Impossible d'initialiser l'indicateur EMA50 directionnelle !!!", __FUNCTION__);
        return(false);
    }

    // EMA20 et EMA50 (M1)
    //--------------------
    m_HandleEMA20_M1  = iMA(Symbol(), PERIOD_M1, 20, 0, MODE_EMA, PRICE_CLOSE);
    if (m_HandleEMA20_M1 == INVALID_HANDLE)
    {
        LOG.ERROR(DATAS.GetStrategyName() + "Impossible d'initialiser l'indicateur EMA20 de management !!!", __FUNCTION__);
        return(false);
    }
    m_HandleEMA50_M1 = iMA(Symbol(), PERIOD_M1, 50, 0, MODE_EMA, PRICE_CLOSE);
    if (m_HandleEMA50_M1 == INVALID_HANDLE)
    {
        LOG.ERROR(DATAS.GetStrategyName() + "Impossible d'initialiser l'indicateur EMA50 de management !!!", __FUNCTION__);
        return(false);
    }

    // ✅ SuperTrend v2 (Soltaniyan) - H1 (Directionnelle)
    // Paramètres : ATRPeriod, Multiplier, SourcePrice, TakeWicksIntoAccount
    // IMPORTANT : le fichier doit s'appeler "supertrend.ex5" (minuscules)
    //------------------------------------------------------------------------
    m_HandleST_D = iCustom(Symbol(), PERIOD_H1, "supertrend",
                           10,                      // ATRPeriod
                           3,                       // Multiplier
                           K_ST_Source,             // SourcePrice
                           true);                   // TakeWicksIntoAccount
    if (m_HandleST_D == INVALID_HANDLE)
    {
        LOG.ERROR(DATAS.GetStrategyName() + "Impossible d'initialiser l'indicateur SuperTrend directionnelle !!!", __FUNCTION__);
        return(false);
    }
    
    // ✅ SuperTrend v2 (Soltaniyan) - M1 (Détection plateaux)
    // Mêmes paramètres que H1
    //-----------------------------------------------------
    m_HandleST_M = iCustom(Symbol(), PERIOD_M1, "supertrend",
                           10,                      // ATRPeriod
                           3,                       // Multiplier
                           K_ST_Source,             // SourcePrice
                           true);                   // TakeWicksIntoAccount
    if (m_HandleST_M == INVALID_HANDLE)
    {
        LOG.ERROR(DATAS.GetStrategyName() + "Impossible d'initialiser l'indicateur SuperTrend M1 (plateaux) !!!", __FUNCTION__);
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

    if (m_HandleEMA20_M5 != INVALID_HANDLE) IndicatorRelease(m_HandleEMA20_M5);
    if (m_HandleEMA50_M5 != INVALID_HANDLE) IndicatorRelease(m_HandleEMA50_M5);
    if (m_HandleEMA20_M1 != INVALID_HANDLE) IndicatorRelease(m_HandleEMA20_M1);
    if (m_HandleEMA50_M1 != INVALID_HANDLE) IndicatorRelease(m_HandleEMA50_M1);
    if (m_HandleST_D     != INVALID_HANDLE) IndicatorRelease(m_HandleST_D);
    if (m_HandleST_M     != INVALID_HANDLE) IndicatorRelease(m_HandleST_M);
    if (m_HandleATR      != INVALID_HANDLE) IndicatorRelease(m_HandleATR);
    
    // ✅ RESET DES PLATEAUX À LA FERMETURE
    //------------------------------------
    ResetSTPlateauTracking();
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
    STRUCT_SYMBOL_CONFIG     l_Config = GetSymbolConfig(I_Symbol_Key);
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
        opr_start      = StringToTime(today_str + " 15:30");
        safe_read_time = opr_start + PeriodSeconds(K_ORB_TF);
        opr_session    = StringToTime(today_str + " 15:45");
        opr_end        = StringToTime(today_str + " 17:30");
        opr_close      = StringToTime(today_str + " 21:00");

        LOG.INFO("Nouvelle journée : OPR Start=" + TimeToString(opr_start) +
                 " | Session=" + TimeToString(opr_session) +
                 " | End="     + TimeToString(opr_end) +
                 " | Close="   + TimeToString(opr_close), __FUNCTION__);
    }

    // ✅ VÉRIFICATION SESSION (Jour + Mois)
    //--------------------------------------
    if (!IsSessionValid())
    {
        if (HasPendingOrderForSymbol())
        {
            LOG.INFO("Session invalide - Annulation des ordres en attente", __FUNCTION__);
            DATAS.CancelPendingOrder();
        }
        return;
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
        // Ne pas spammer CancelPendingOrder() si aucun ordre n'est en attente
        // (ce bloc est appelé à chaque tick + chaque seconde par OnTimer).
        if (HasPendingOrderForSymbol())
        {
            DATAS.CancelPendingOrder();
        }
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
        if (HasPendingOrderForSymbol())
        {
            LOG.INFO("OPR - End dépassé - Annulation ordres en attente", __FUNCTION__);
            DATAS.CancelPendingOrder();
        }
        return;
    }
    
    // Après le bloc qui lit opr_high et opr_low, avant "=== ANALYSE INDICATEURS ==="
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

    // === ANALYSE INDICATEURS ===
    //----------------------------
    ENUM_TREND st_trend  = eT_Unknown;
    ENUM_TREND ema_trend = eT_Unknown;
    
    if (!CheckSuperTrend(st_trend)) return;
    if (!CheckEMA(ema_trend)) return;

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
    double offset = l_Config.offset_points;

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
            l_Datas.TakeProfit    = 0.0;
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
            l_Datas.TakeProfit    = 0.0;
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
            l_Datas.TakeProfit    = 0.0;
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
            l_Datas.TakeProfit    = 0.0;
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
                 " , SL = "        + DoubleToString(l_Datas.StopLoss,   Digits()), __FUNCTION__);

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
//| Appelée à chaque tick depuis OnTick() et OnTimer().              |
//| Ordre (spec §25) :                                                |
//|  1. Lecture tick                                                  |
//|  2. Zone NEWS → annuler pending orders (NE bloque PAS la gestion)|
//|  3. Si position ouverte :                                         |
//|       a. Sortie EMA M1 (prioritaire) → fermer + return           |
//|       b. Protection SL par plateaux ST M1                         |
//|  4. Zone NEWS → return (bloque nouvelles entrées)                 |
//|  5. Divergence ST/EMA → annulation pending orders                 |
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
    STRUCT_SYMBOL_CONFIG l_Config    = GetSymbolConfig(I_Symbol_Key);
    ENUM_TREND           l_StTrend   = eT_Unknown;
    ENUM_TREND           l_EmaTrend  = eT_Unknown;

    // Lecture du tick courant
    //------------------------
    if (!SymbolInfoTick(Symbol(), l_Tick))
    {
        LOG.WARNING("ManagePositions : Impossible de lire le tick", __FUNCTION__);
        return;
    }

    // Flag zone NEWS (n'affecte QUE les nouvelles entrées)
    //------------------------------------------------------
    bool in_news_zone = !PARAM.OutsideSecurityZone();

    // 1. ZONE NEWS : annuler les ordres en attente (mais ne pas bloquer la gestion)
    //-------------------------------------------------------------------------------
    if (in_news_zone)
    {
        if (HasPendingOrderForSymbol())
        {
            LOG.INFO("🔴 Zone NEWS (tick) - Annulation immédiate des ordres en attente", __FUNCTION__);
            DATAS.CancelPendingOrder();
        }
    }

    // 2. POSITION EXISTANTE : gestion prioritaire (même en zone NEWS)
    //-----------------------------------------------------------------
    if (HasPositionForSymbol())
    {
        // 2a. SORTIE EMA M1 — priorité absolue, reste active en zone NEWS
        //     La ST n'est PAS une condition de sortie directionnelle.
        //----------------------------------------------------------------
        if (CheckTrendExitOnM1())
        {
            // CheckTrendExitOnM1 a déjà loggé + fermé la position.
            // NE PAS continuer à construire un plateau sur une position fermée.
            return;
        }

        // 2b. Gestion du SL post-entrée : un seul mode actif à la fois (CORR1).
        //     - SL_MODE_R_BE       : ApplyBreakEven() (ancien)
        //     - SL_MODE_ST_PLATEAU : UpdateSTPlateauDetection() (nouveau)
        //     Les deux NE doivent JAMAIS tourner simultanément.
        //----------------------------------------------------------------------
        if (I_SL_Management_Mode == SL_MODE_R_BE)
        {
            if (l_Config.apply_be)
            {
                ApplyBreakEven(l_Tick);
            }
        }
        else // SL_MODE_ST_PLATEAU
        {
            // CORR3 : un seul OrderSend SLTP par tick. Reset en début de tick.
            m_SLAttemptedThisTick = false;

            // Détection structurelle : UNE observation par bougie M1 clôturée.
            // Peut déclencher un TryMoveSLToPlateauLevel() immédiat — auquel cas
            // m_SLAttemptedThisTick passe à true.
            UpdateSTPlateauDetection(l_Tick);

            // Exécution d'une modif SL déjà décidée : retentée à CHAQUE tick
            // indépendamment de la détection M1 (CORR2, CORR13, CORR14).
            // CORR3 : ne PAS re-tenter sur le même tick si la détection vient
            // déjà de le faire — le retry commence au tick suivant.
            if (m_PendingSLMove && !m_SLAttemptedThisTick)
            {
                RetryPendingSLMove();
            }
        }
    }
    else
    {
        // Pas de position ouverte → s'assurer que le tracking plateau est inactif
        // (utile après une fermeture manuelle / TP serveur / etc.) (CORR4)
        //------------------------------------------------------------------------
        if (m_STPlateau.active)
        {
            ResetSTPlateauTracking();
        }
    }

    // 3. ZONE NEWS : bloquer toute nouvelle entrée (return)
    //-------------------------------------------------------
    if (in_news_zone)
    {
        return;
    }

    // 4. DIVERGENCE ST/EMA (uniquement hors zone NEWS)
    //--------------------------------------------------
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

        // ✅ Initialiser le tracking des plateaux ST M1
        // Le ticket du deal n'est pas un ticket de position ; on laissera
        // UpdateSTPlateauTracking retrouver la position via Symbol()+Magic.
        //---------------------------------------------
        ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(l_Ticket, DEAL_TYPE);
        ENUM_TREND trend = (deal_type == DEAL_BUY) ? eT_Bull : eT_Bear;
        InitSTPlateauTracking(trend, 0);

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

            // ✅ Initialiser le tracking des plateaux ST M1
            // La position n'est peut-être pas encore visible à ce tick exact :
            // UpdateSTPlateauDetection s'assurera via HasPositionForSymbol() et
            // fixera le ticket réel dès qu'elle sera disponible.
            //---------------------------------------------
            InitSTPlateauTracking(eT_Bull, 0);

            return(true);
        }
        if (type == ORDER_TYPE_SELL_STOP && i_tick.bid <= entry)
        {
            LOG.INFO("🔒 Cassure OPR détectée — verrouillage journée (SELL)", __FUNCTION__);
            m_PositionOpened = true;

            // ✅ Initialiser le tracking des plateaux ST M1
            //---------------------------------------------
            InitSTPlateauTracking(eT_Bear, 0);

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

        // ✅ Initialiser le tracking des plateaux ST M1 avec le ticket réel
        //-----------------------------------------------------------------
        ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        ENUM_TREND trend = (pos_type == POSITION_TYPE_BUY) ? eT_Bull : eT_Bear;
        InitSTPlateauTracking(trend, l_Ticket);

        return(true);
    }
    
    return(false);
}

//+------------------------------------------------------------------+
//| ✅ InitSTPlateauTracking                                         |
//| Initialise le suivi des plateaux SuperTrend M1.                  |
//| Ne reconstruit PAS d'historique de plateaux (spec §27).          |
//| INPUT:                                                           |
//|  i_expected_direction : Direction attendue (eT_Bull ou eT_Bear) |
//|  i_position_ticket    : Ticket de la position (0 si pas encore    |
//|                         visible — sera résolu au prochain tick)   |
//| OUTPUT:                                                          |
//|  None                                                            |
//+------------------------------------------------------------------+
void CStrategy::InitSTPlateauTracking(const ENUM_TREND i_expected_direction,
                                     const ulong i_position_ticket)
{
    // Réinitialiser l'état du suivi (ne pas réutiliser d'ancien état)
    //----------------------------------------------------------------
    ZeroMemory(m_STPlateau);

    m_STPlateau.expected_direction      = i_expected_direction;
    m_STPlateau.active                  = true;
    m_STPlateau.current_candidate.valid = false;
    m_STPlateau.current_candidate.level = 0;
    m_STPlateau.current_candidate.count = 0;
    m_STPlateau.last_confirmed.valid    = false;

    m_LastProcessedM1Bar      = 0;
    m_STTrackedPositionTicket = i_position_ticket;

    string direction = (i_expected_direction == eT_Bull) ? "📈 LONG (UP)" : "📉 SHORT (DOWN)";
    string ticket_s  = (i_position_ticket == 0) ? "<pending>" : IntegerToString(i_position_ticket);
    LOG.INFO("[ST PLATEAU] INIT | Direction: " + direction +
             " | Ticket: " + ticket_s, __FUNCTION__);
    LOG.INFO("[ST PLATEAU] Tracking démarré sans historique précédent", __FUNCTION__);
    ClearPendingSLMove();
}

//+------------------------------------------------------------------+
//| ✅ UpdateSTPlateauDetection                                      |
//| Met à jour la détection des plateaux SuperTrend M1.              |
//| Une seule observation par bougie M1 clôturée (shift=1).          |
//| Les directions opposées à expected_direction sont ignorées.       |
//| Un retour sur last_confirmed.level est ignoré.                    |
//| INPUT:                                                           |
//|  i_tick : Le tick courant                                        |
//| OUTPUT:                                                          |
//|  None                                                            |
//+------------------------------------------------------------------+
void CStrategy::UpdateSTPlateauDetection(const MqlTick &i_tick)
{
    // 1. Tracking actif ?
    //--------------------
    if (!m_STPlateau.active) return;

    // 2. Garantie d'identité de la position suivie (CORR3).
    //    Si le ticket suivi ne correspond plus à une position réelle de cet EA
    //    (fermeture + réouverture rapide, ou redémarrage), on s'aligne sur la
    //    position courante. ManagePositions garantit qu'il existe au moins une
    //    position pour ce symbole+magic.
    //-------------------------------------------------------------------------
    EnsureTrackingMatchesPosition();

    // 3. Anti-doublon : traiter une seule fois par bougie M1 (spec §3, CORR1).
    //    IMPORTANT : la bougie n'est marquée "traitée" qu'APRÈS validation
    //    complète de CopyBuffer ET des valeurs ST. Si la donnée n'est pas
    //    encore disponible, on sort SANS modifier m_LastProcessedM1Bar afin
    //    de pouvoir retenter la même bougie au tick suivant.
    //-------------------------------------------------------------------------
    datetime current_m1_time = iTime(Symbol(), PERIOD_M1, 0);
    if (current_m1_time == 0) return;
    if (current_m1_time == m_LastProcessedM1Bar) return;

    // 4. Lire la ST M1 sur la DERNIÈRE BOUGIE CLÔTURÉE (shift=1, spec §2)
    //    Buffer 0 = valeur ST, buffer 2 = direction ST.
    //    Si CopyBuffer échoue, on sort SANS marquer la bougie comme traitée.
    //-------------------------------------------------------------------
    double buffer_value[1];
    double buffer_dir[1];

    if (CopyBuffer(m_HandleST_M, 0, 1, 1, buffer_value) != 1) return;
    if (CopyBuffer(m_HandleST_M, 2, 1, 1, buffer_dir)    != 1) return;

    double st_value_m1     = buffer_value[0];
    double st_direction_m1 = buffer_dir[0];

    // 5. Valeurs invalides : ST pas encore prête.
    //    On sort SANS marquer la bougie comme traitée (CORR1).
    //--------------------------------------------
    if (st_value_m1 <= 0.0) return;
    if (st_direction_m1 == 0.0) return;

    // 6. Donnée validée : on marque la bougie comme traitée — définitivement.
    //------------------------------------------------------------------------
    m_LastProcessedM1Bar = current_m1_time;

    // 7. Direction opposée → IGNORE complètement (spec §4)
    //    Ne crée pas / ne reset pas / ne confirme pas / ne déplace pas le SL.
    //------------------------------------------------------------------------
    ENUM_TREND st_detected = (st_direction_m1 > 0.0) ? eT_Bull : eT_Bear;
    if (st_detected != m_STPlateau.expected_direction)
    {
        string exp_s = (m_STPlateau.expected_direction == eT_Bull) ? "Bull" : "Bear";
        string det_s = (st_detected == eT_Bull) ? "Bull" : "Bear";
        LOG.INFO("[ST PLATEAU] Direction opposée ignorée | Expected=" + exp_s +
                 " Detected=" + det_s, __FUNCTION__);
        return;
    }

    // 8. Calcul E(ST) = floor(valeur)
    //--------------------------------
    int current_level = (int)MathFloor(st_value_m1);

    // 9. Retour sur le dernier plateau confirmé → IGNORE (spec §8)
    //-------------------------------------------------------------
    if (m_STPlateau.last_confirmed.valid && current_level == m_STPlateau.last_confirmed.level)
    {
        LOG.INFO("[ST PLATEAU] Retour plateau confirmé ignoré | Level=" +
                 IntegerToString(current_level), __FUNCTION__);
        return;
    }

    // 10. Gestion du candidat
    //--------------------------
    if (!m_STPlateau.current_candidate.valid && m_STPlateau.current_candidate.count == 0)
    {
        // 10a. Aucun candidat → en créer un nouveau (spec §9)
        //---------------------------------------------------
        m_STPlateau.current_candidate.level      = current_level;
        m_STPlateau.current_candidate.first_value = st_value_m1; // immuable (spec §10)
        m_STPlateau.current_candidate.count      = 1;
        m_STPlateau.current_candidate.valid      = false;

        LOG.INFO("[ST PLATEAU] Nouveau candidat | Level=" + IntegerToString(current_level) +
                 " FirstValue=" + DoubleToString(st_value_m1, _Digits), __FUNCTION__);
    }
    else if (current_level == m_STPlateau.current_candidate.level)
    {
        // 10b. Même niveau → incrémenter
        //-------------------------------
        m_STPlateau.current_candidate.count++;

        LOG.INFO("[ST PLATEAU] Occurrence | Level=" + IntegerToString(current_level) +
                 " Count=" + IntegerToString(m_STPlateau.current_candidate.count), __FUNCTION__);

        // 10c. Confirmation ?
        //-------------------
        if (m_STPlateau.current_candidate.count >= (int)I_ST_Plateau_MinCount)
        {
            m_STPlateau.current_candidate.valid = true;

            LOG.INFO("[ST PLATEAU] ✅ Confirmé | Level=" + IntegerToString(current_level) +
                     " Count=" + IntegerToString(m_STPlateau.current_candidate.count) +
                     " FirstValue=" + DoubleToString(m_STPlateau.current_candidate.first_value, _Digits),
                     __FUNCTION__);

            // 10d. Déplacement du SL (spec §6, §7, CORR2) :
            //    - Premier plateau  : stocker dans last_confirmed, NE PAS bouger le SL.
            //    - Plateau suivant  : SL = last_confirmed.first_value (plateau PRÉCÉDENT).
            //      On tente la modif UNE fois ici. En cas d'échec broker, on enregistre
            //      une cible SL en attente (m_PendingSL*) qui sera retentée à chaque tick
            //      par ManagePositions. Le plateau confirmé est TOUJOURS rotationné :
            //      la structure et l'exécution sont deux états séparés.
            if (!m_STPlateau.last_confirmed.valid)
            {
                // Premier plateau confirmé : pas de déplacement (spec §6)
                LOG.INFO("[ST PLATEAU] Premier plateau confirmé, aucun déplacement SL | Level=" +
                         IntegerToString(current_level), __FUNCTION__);

                m_STPlateau.last_confirmed = m_STPlateau.current_candidate;
                ZeroMemory(m_STPlateau.current_candidate);
            }
            else
            {
                // Plateau B (ou suivant) confirmé.
                // Cible = last_confirmed.first_value (plateau A) — AVANT rotation.
                double target_sl        = m_STPlateau.last_confirmed.first_value;
                int    target_level     = m_STPlateau.last_confirmed.level;
                double target_first_val = m_STPlateau.last_confirmed.first_value;

                // TOUJOURS rotationner le plateau confirmé (CORR2 : la structure
                // et l'exécution sont indépendantes).
                m_STPlateau.last_confirmed = m_STPlateau.current_candidate;
                ZeroMemory(m_STPlateau.current_candidate);

                // CORR3 : on s'apprête à tenter une modif SL sur ce tick.
                m_SLAttemptedThisTick = true;

                // Tenter immédiatement la modif. Sur échec, enregistrer une cible
                // SL en attente — sera retentée à chaque tick suivant par
                // RetryPendingSLMove() (jamais sur le même tick que la tentative initiale).
                if (!TryMoveSLToPlateauLevel(target_sl, target_level, target_first_val))
                {
                    // CORR2 : ne JAMAIS dégrader une cible pending existante.
                    // La cible pending représente une protection déjà identifiée
                    // et refusée temporairement par le broker — elle ne doit pas
                    // être remplacée par une cible moins favorable.
                    bool store_pending = true;

                    if (m_PendingSLMove)
                    {
                        // Récupérer le type de position pour la comparaison.
                        ENUM_POSITION_TYPE pos_type = POSITION_TYPE_BUY;
                        if (PositionSelectByTicket(m_STTrackedPositionTicket))
                        {
                            pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                        }

                        // Comparer avec le pending existant.
                        if (!IsMoreFavorableSL(target_sl, m_PendingSL, pos_type))
                        {
                            store_pending = false;
                            LOG.INFO("[ST PLATEAU] Cible pending conservée (plus favorable) | "
                                     "Existing=" + DoubleToString(m_PendingSL, _Digits) +
                                     " Rejected=" + DoubleToString(target_sl, _Digits), __FUNCTION__);
                        }
                    }

                    if (store_pending)
                    {
                        m_PendingSLMove       = true;
                        m_PendingSL           = target_sl;
                        m_PendingSLLevel      = target_level;
                        m_PendingSLFirstValue = target_first_val;
                        LOG.INFO("[ST PLATEAU] SL mis en attente (retry par tick) | Target=" +
                                 DoubleToString(target_sl, _Digits) +
                                 " Level=" + IntegerToString(target_level), __FUNCTION__);
                    }
                }
                else
                {
                    ClearPendingSLMove();
                }
            }
        }
    }
    else
    {
        // 10e. Changement de niveau : abandonner le candidat, en créer un nouveau (spec §9)
        //--------------------------------------------------------------------------------
        LOG.INFO("[ST PLATEAU] Changement de niveau | OldLevel=" +
                 IntegerToString(m_STPlateau.current_candidate.level) +
                 " OldCount=" + IntegerToString(m_STPlateau.current_candidate.count) +
                 " → NewLevel=" + IntegerToString(current_level), __FUNCTION__);

        m_STPlateau.current_candidate.level       = current_level;
        m_STPlateau.current_candidate.first_value = st_value_m1;
        m_STPlateau.current_candidate.count       = 1;
        m_STPlateau.current_candidate.valid       = false;
    }
}

//+------------------------------------------------------------------+
//| ✅ ResetSTPlateauTracking                                        |
//| Réinitialise le suivi des plateaux                               |
//| Appelée quand une position se ferme                              |
//| INPUT:                                                           |
//|  None                                                            |
//| OUTPUT:                                                          |
//|  None                                                            |
//+------------------------------------------------------------------+
void CStrategy::ResetSTPlateauTracking(void)
{
    if (m_STPlateau.active)
    {
        LOG.INFO("[ST PLATEAU] Position reset | Ticket=" +
                 IntegerToString(m_STTrackedPositionTicket), __FUNCTION__);
    }

    ZeroMemory(m_STPlateau);
    m_STPlateau.active            = false;
    m_LastProcessedM1Bar          = 0;
    m_STTrackedPositionTicket     = 0;

    ClearPendingSLMove();
}

//+------------------------------------------------------------------+
//| ✅ ClearPendingSLMove                                             |
//| Remet à zéro l'état "modif SL en attente".                       |
//+------------------------------------------------------------------+
void CStrategy::ClearPendingSLMove(void)
{
    m_PendingSLMove       = false;
    m_PendingSL           = 0.0;
    m_PendingSLLevel      = 0;
    m_PendingSLFirstValue = 0.0;
}

//+------------------------------------------------------------------+
//| ✅ IsMoreFavorableSL                                              |
//| Indique si `i_candidate` est un SL plus favorable que             |
//| `i_reference` pour le type de position donné (CORR2).             |
//|   BUY  : plus le SL est HAUT, plus c'est favorable.               |
//|   SELL : plus le SL est BAS, plus c'est favorable.                 |
//| Un SL égal n'est PAS plus favorable (on ne dégrade pas).          |
//+------------------------------------------------------------------+
bool CStrategy::IsMoreFavorableSL(const double i_candidate,
                                  const double i_reference,
                                  const ENUM_POSITION_TYPE i_type)
{
    if (i_type == POSITION_TYPE_BUY)
    {
        return(i_candidate > i_reference);
    }
    else // POSITION_TYPE_SELL
    {
        return(i_candidate < i_reference);
    }
}

//+------------------------------------------------------------------+
//| ✅ IsOurPositionTicket                                            |
//| Vérifie qu'un ticket correspond à une position réelle de cet EA. |
//+------------------------------------------------------------------+
bool CStrategy::IsOurPositionTicket(const ulong i_ticket)
{
    if (i_ticket == 0) return(false);
    if (!PositionSelectByTicket(i_ticket)) return(false);
    if (PositionGetString(POSITION_SYMBOL)  != Symbol())              return(false);
    if (PositionGetInteger(POSITION_MAGIC)  != (K_Magic + I_Robot_ID)) return(false);
    return(true);
}

//+------------------------------------------------------------------+
//| ✅ FindOurPositionTicket                                          |
//| Retourne le ticket de la première position de cet EA, 0 sinon.   |
//+------------------------------------------------------------------+
ulong CStrategy::FindOurPositionTicket(void)
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong pos_ticket = PositionGetTicket(i);
        if (PositionGetString(POSITION_SYMBOL)  == Symbol() &&
            PositionGetInteger(POSITION_MAGIC)  == (K_Magic + I_Robot_ID))
        {
            return(pos_ticket);
        }
    }
    return(0);
}

//+------------------------------------------------------------------+
//| ✅ EnsureTrackingMatchesPosition                                 |
//| CORR3 / CORR4 :                                                   |
//|  - Si le ticket suivi n'existe plus (position fermée) MAIS qu'une |
//|    autre position du même EA est ouverte (réouverture rapide),    |
//|    on RESET complètement le tracking et on repart sur la nouvelle |
//|    position avec un état neuf.                                    |
//|  - Si aucun ticket n'était suivi (initialisation post-pending),   |
//|    on l'associe simplement à la position courante.                |
//|  - Si le ticket suivi est toujours valide, on ne touche à rien.   |
//+------------------------------------------------------------------+
void CStrategy::EnsureTrackingMatchesPosition(void)
{
    // Cas nominal : ticket suivi toujours valide.
    if (IsOurPositionTicket(m_STTrackedPositionTicket)) return;

    // Le ticket suivi n'est plus valide. Y a-t-il une nouvelle position ?
    ulong new_ticket = FindOurPositionTicket();
    if (new_ticket == 0)
    {
        // Aucune position de cet EA — ManagePositions gérera le reset.
        return;
    }

    // Une nouvelle position existe : RESET COMPLET puis ré-init neuve.
    ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    ENUM_TREND trend = (pos_type == POSITION_TYPE_BUY) ? eT_Bull : eT_Bear;

    LOG.INFO("[ST PLATEAU] Nouveau ticket détecté — reset complet du tracking | OldTicket=" +
             IntegerToString(m_STTrackedPositionTicket) + " NewTicket=" +
             IntegerToString(new_ticket), __FUNCTION__);

    InitSTPlateauTracking(trend, new_ticket);
}

//+------------------------------------------------------------------+
//| ✅ RetryPendingSLMove                                             |
//| Retente à chaque tick une modif SL déjà décidée mais échouée.    |
//| INDÉPENDANT de la détection M1 (CORR2, CORR13, CORR14).          |
//+------------------------------------------------------------------+
void CStrategy::RetryPendingSLMove(void)
{
    if (!m_PendingSLMove) return;

    // La position doit toujours exister.
    if (!IsOurPositionTicket(m_STTrackedPositionTicket))
    {
        // Position fermée entre-temps : abandon de la cible.
        ClearPendingSLMove();
        return;
    }

    LOG.INFO("[ST PLATEAU] SL retry | Target=" + DoubleToString(m_PendingSL, _Digits) +
             " Level=" + IntegerToString(m_PendingSLLevel), __FUNCTION__);

    if (TryMoveSLToPlateauLevel(m_PendingSL, m_PendingSLLevel, m_PendingSLFirstValue))
    {
        ClearPendingSLMove();
    }
    // Sinon : on garde la cible et on retentera au prochain tick.
}

//+------------------------------------------------------------------+
//| ✅ NormalizeToTickSize                                            |
//| Aligne un prix sur le tick size du symbole (spec §18).           |
//| INPUT:                                                           |
//|  i_price : prix brut                                             |
//| OUTPUT:                                                          |
//|  prix aligné au tick size, puis normalisé à _Digits              |
//+------------------------------------------------------------------+
double CStrategy::NormalizeToTickSize(const double i_price)
{
    double tick_size = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    if (tick_size <= 0.0) return(NormalizeDouble(i_price, _Digits));
    double aligned = MathRound(i_price / tick_size) * tick_size;
    return(NormalizeDouble(aligned, _Digits));
}

//+------------------------------------------------------------------+
//| ✅ TryMoveSLToPlateauLevel                                       |
//| Tente de déplacer le SL vers une cible explicite.                |
//| Garde-fous :                                                     |
//|  - SL ne recule jamais (spec §11, CORR11)                        |
//|  - respecte SYMBOL_TRADE_STOPS_LEVEL et SYMBOL_TRADE_FREEZE_LEVEL|
//|  - aligne au SYMBOL_TRADE_TICK_SIZE (spec §18, CORR13)           |
//|  - conserve le TP existant, n'impose pas ORDER_FILLING_FOK       |
//| INPUT:                                                           |
//|  i_target_sl        : prix cible brut (first_value du plateau)    |
//|  i_target_level     : niveau entier du plateau cible (log)        |
//|  i_target_first_val : first_value du plateau cible (log)          |
//| OUTPUT:                                                          |
//|  true si le SL a été déplacé avec succès                         |
//+------------------------------------------------------------------+
bool CStrategy::TryMoveSLToPlateauLevel(const double i_target_sl,
                                       const int    i_target_level,
                                       const double i_target_first_val)
{
    // 1. Cible explicite obligatoire
    //--------------------------------
    if (i_target_sl <= 0.0) return(false);

    // 2. Sélectionner la position suivie (ticket si connu, sinon via Symbol+Magic)
    //-----------------------------------------------------------------------------
    ulong ticket = m_STTrackedPositionTicket;
    if (ticket == 0 || !PositionSelectByTicket(ticket))
    {
        ticket = 0;
        for (int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong pos_ticket = PositionGetTicket(i);
            if (PositionGetString(POSITION_SYMBOL)  == Symbol() &&
                PositionGetInteger(POSITION_MAGIC)  == (K_Magic + I_Robot_ID))
            {
                ticket = pos_ticket;
                break;
            }
        }
        if (ticket == 0 || !PositionSelectByTicket(ticket))
        {
            LOG.WARNING("[ST PLATEAU] Position non trouvée pour déplacement SL", __FUNCTION__);
            return(false);
        }
        m_STTrackedPositionTicket = ticket;
    }

    // 3. Données de la position
    //--------------------------
    double               current_sl = PositionGetDouble(POSITION_SL);
    double               current_tp = PositionGetDouble(POSITION_TP);
    ENUM_POSITION_TYPE   pos_type   = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    double               new_sl     = i_target_sl;

    int    prev_level       = i_target_level;
    double prev_first_value = i_target_first_val;

    // 4. Aligner au tick size puis normaliser (spec §18)
    //----------------------------------------------------
    new_sl     = NormalizeToTickSize(new_sl);
    current_sl = NormalizeDouble(current_sl, _Digits);

    // 5. Garde-fou "SL ne recule jamais" (spec §11)
    //----------------------------------------------
    if (pos_type == POSITION_TYPE_BUY)
    {
        if (new_sl <= current_sl)
        {
            LOG.INFO("[ST PLATEAU] SL refusé car non favorable (BUY) | OldSL=" +
                     DoubleToString(current_sl, _Digits) + " NewSL=" +
                     DoubleToString(new_sl, _Digits), __FUNCTION__);
            return(false);
        }
    }
    else if (pos_type == POSITION_TYPE_SELL)
    {
        if (new_sl >= current_sl)
        {
            LOG.INFO("[ST PLATEAU] SL refusé car non favorable (SELL) | OldSL=" +
                     DoubleToString(current_sl, _Digits) + " NewSL=" +
                     DoubleToString(new_sl, _Digits), __FUNCTION__);
            return(false);
        }
    }
    else
    {
        return(false);
    }

    // 6. Contraintes broker (spec §17) — distance minimale
    //------------------------------------------------------
    MqlTick tick;
    if (!SymbolInfoTick(Symbol(), tick))
    {
        LOG.WARNING("[ST PLATEAU] SymbolInfoTick échec — déplacement SL annulé", __FUNCTION__);
        return(false);
    }

    double stop_level_points   = (double)SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL);
    double freeze_level_points = (double)SymbolInfoInteger(Symbol(), SYMBOL_TRADE_FREEZE_LEVEL);
    double required_distance   = MathMax(stop_level_points, freeze_level_points) * _Point;

    bool   broker_ok = true;
    string reject_reason = "";

    if (pos_type == POSITION_TYPE_BUY)
    {
        // SL < Bid et Bid - new_sl >= required_distance
        if (new_sl >= tick.bid)
        {
            broker_ok     = false;
            reject_reason = "NewSL >= Bid";
        }
        else if ((tick.bid - new_sl) < required_distance)
        {
            broker_ok     = false;
            reject_reason = "Bid-NewSL < required_distance";
        }
    }
    else // SELL
    {
        // SL > Ask et new_sl - Ask >= required_distance
        if (new_sl <= tick.ask)
        {
            broker_ok     = false;
            reject_reason = "NewSL <= Ask";
        }
        else if ((new_sl - tick.ask) < required_distance)
        {
            broker_ok     = false;
            reject_reason = "NewSL-Ask < required_distance";
        }
    }

    if (!broker_ok)
    {
        LOG.WARNING("[ST PLATEAU] SL refusé broker | " + reject_reason +
                    " | StopsLevel=" + DoubleToString(stop_level_points, 0) +
                    "pts FreezeLevel=" + DoubleToString(freeze_level_points, 0) +
                    "pts | Bid=" + DoubleToString(tick.bid, _Digits) +
                    " Ask=" + DoubleToString(tick.ask, _Digits) +
                    " NewSL=" + DoubleToString(new_sl, _Digits), __FUNCTION__);
        return(false);
    }

    // 7. Requête TRADE_ACTION_SLTP minimale (spec §19) — pas de type_filling
    //------------------------------------------------------------------------
    MqlTradeRequest request;
    MqlTradeResult  result;
    ZeroMemory(request);
    ZeroMemory(result);

    request.action   = TRADE_ACTION_SLTP;
    request.symbol   = Symbol();
    request.position = ticket;
    request.sl       = new_sl;
    request.tp       = current_tp; // conserver le TP existant (TP reste à 0)

    LOG.INFO("[ST PLATEAU] SL demandé | Ticket=" + IntegerToString(ticket) +
             " OldSL=" + DoubleToString(current_sl, _Digits) +
             " NewSL=" + DoubleToString(new_sl, _Digits) +
             " PreviousPlateauLevel=" + IntegerToString(prev_level) +
             " PreviousPlateauFirstValue=" + DoubleToString(prev_first_value, _Digits),
             __FUNCTION__);

    if (!OrderSend(request, result))
    {
        LOG.WARNING("[ST PLATEAU] OrderSend échec | Retcode=" + IntegerToString(result.retcode) +
                    " Comment=" + result.comment, __FUNCTION__);
        return(false);
    }

    if (result.retcode == TRADE_RETCODE_DONE ||
        result.retcode == TRADE_RETCODE_PLACED ||
        result.retcode == TRADE_RETCODE_DONE_PARTIAL)
    {
        LOG.INFO("[ST PLATEAU] ✅ SL déplacé | Ticket=" + IntegerToString(ticket) +
                 " OldSL=" + DoubleToString(current_sl, _Digits) +
                 " NewSL=" + DoubleToString(new_sl, _Digits) +
                 " Level=" + IntegerToString(prev_level) +
                 " FirstValue=" + DoubleToString(prev_first_value, _Digits) +
                 " Retcode=" + IntegerToString(result.retcode), __FUNCTION__);
        return(true);
    }

    LOG.WARNING("[ST PLATEAU] SL refusé broker | Retcode=" + IntegerToString(result.retcode) +
                " Comment=" + result.comment +
                " StopsLevel=" + DoubleToString(stop_level_points, 0) + "pts" +
                " FreezeLevel=" + DoubleToString(freeze_level_points, 0) + "pts" +
                " Bid=" + DoubleToString(tick.bid, _Digits) +
                " Ask=" + DoubleToString(tick.ask, _Digits) +
                " NewSL=" + DoubleToString(new_sl, _Digits), __FUNCTION__);
    return(false);
}

//+------------------------------------------------------------------+
//| CheckTrendExitOnM1                                               |
//| Sortie si la tendance EMA M1 change, ST M1 sert d'alerte/confirm. |
//| L'EMA a la priorité si ST et EMA ne parlent pas le même langage. |
//| INPUT:                                                           |
//|  None                                                            |
//| OUTPUT:                                                          |
//|  TRUE si au moins une position a été fermée                     |
//+------------------------------------------------------------------+
bool CStrategy::CheckTrendExitOnM1(void)
{
    double ema20[];
    double ema50[];
    double st_dir[];

    if (CopyBuffer(m_HandleEMA20_M1, 0, 1, 1, ema20) != 1)
    {
        LOG.WARNING(DATAS.GetStrategyName() + "EMA20 M1 indisponible pour la sortie", __FUNCTION__);
        return(false);
    }
    if (CopyBuffer(m_HandleEMA50_M1, 0, 1, 1, ema50) != 1)
    {
        LOG.WARNING(DATAS.GetStrategyName() + "EMA50 M1 indisponible pour la sortie", __FUNCTION__);
        return(false);
    }
    if (CopyBuffer(m_HandleST_M, 2, 1, 1, st_dir) != 1)
    {
        LOG.WARNING(DATAS.GetStrategyName() + "SuperTrend M1 indisponible pour la sortie", __FUNCTION__);
        return(false);
    }

    ArraySetAsSeries(ema20, true);
    ArraySetAsSeries(ema50, true);
    ArraySetAsSeries(st_dir, true);

    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong l_Ticket = PositionGetTicket(i);
        if (PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
        if (PositionGetInteger(POSITION_MAGIC) != (K_Magic + I_Robot_ID)) continue;

        ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        bool ema_exit = false;
        bool st_flip  = false;

        if (pos_type == POSITION_TYPE_BUY)
        {
            ema_exit = (ema20[0] < ema50[0]);
            st_flip  = (st_dir[0] < 0.0);
        }
        else if (pos_type == POSITION_TYPE_SELL)
        {
            ema_exit = (ema20[0] > ema50[0]);
            st_flip  = (st_dir[0] > 0.0);
        }
        else
        {
            continue;
        }

        if (!ema_exit) continue;

        LOG.INFO("[Sortie EMA] Ticket=" + IntegerToString(l_Ticket) +
                 " | EMA20=" + DoubleToString(ema20[0], _Digits) +
                 " | EMA50=" + DoubleToString(ema50[0], _Digits) +
                 (st_flip ? " | ST M1 confirme (flip)" : " | ST M1 ne confirme pas"), __FUNCTION__);

        if (ClosePositionByTicket(l_Ticket, pos_type))
        {
            return(true);
        }
    }

    return(false);
}

//+------------------------------------------------------------------+
//| ClosePositionByTicket                                            |
//| Fermeture d'une position spécifique sur signal EMA/ST             |
//| INPUT:                                                           |
//|  i_ticket : ticket de position                                    |
//|  i_position_type : BUY ou SELL                                    |
//| OUTPUT:                                                          |
//|  TRUE si la fermeture a été envoyée avec succès                  |
//+------------------------------------------------------------------+
bool CStrategy::ClosePositionByTicket(const ulong i_ticket, const ENUM_POSITION_TYPE i_position_type)
{
    if (!PositionSelectByTicket(i_ticket))
    {
        LOG.WARNING("Position introuvable pour fermeture | Ticket=" + IntegerToString(i_ticket), __FUNCTION__);
        return(false);
    }

    MqlTradeRequest l_Request;
    MqlTradeResult  l_Result;
    ZeroMemory(l_Request);
    ZeroMemory(l_Result);

    l_Request.action   = TRADE_ACTION_DEAL;
    l_Request.position = i_ticket;
    l_Request.symbol   = Symbol();
    l_Request.volume   = PositionGetDouble(POSITION_VOLUME);
    l_Request.price    = (i_position_type == POSITION_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_BID) : SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    l_Request.type     = (i_position_type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    l_Request.magic    = K_Magic + I_Robot_ID;
    l_Request.deviation = 20;

    ResetLastError();
    if (!OrderSend(l_Request, l_Result))
    {
        LOG.ERROR("OrderSend fermeture échec | Ticket=" + IntegerToString(i_ticket) +
                  " | Error=" + IntegerToString(GetLastError()), __FUNCTION__);
        return(false);
    }

    if (l_Result.retcode == TRADE_RETCODE_DONE ||
        l_Result.retcode == TRADE_RETCODE_PLACED ||
        l_Result.retcode == TRADE_RETCODE_DONE_PARTIAL)
    {
        LOG.INFO("✅ Position fermée par EMA M1 | Ticket=" + IntegerToString(i_ticket) +
                 " | Type=" + EnumToString(i_position_type) +
                 " | Prix=" + DoubleToString(l_Request.price, _Digits), __FUNCTION__);
        return(true);
    }

    LOG.WARNING("Fermeture refusée | Ticket=" + IntegerToString(i_ticket) +
                " | Retcode=" + IntegerToString(l_Result.retcode) +
                " | Comment=" + l_Result.comment, __FUNCTION__);
    return(false);
}

//+------------------------------------------------------------------+
//| IsSessionValid                                                   |
//| Vérifie si le jour et le mois sont valides pour trader           |
//| La configuration est lue depuis GetSymbolConfig()                |
//| INPUT:                                                           |
//|  None                                                            |
//| OUTPUT:                                                          |
//|  TRUE si le jour et le mois sont valides                         |
//+------------------------------------------------------------------+
bool CStrategy::IsSessionValid(void)
{
    STRUCT_SYMBOL_CONFIG l_Config = GetSymbolConfig(I_Symbol_Key);
    MqlDateTime          l_Dt;
    TimeCurrent(l_Dt);

    // Vérification des mois exclus
    //------------------------------
    for (int i = 0; i < l_Config.nb_excl_months; i++)
    {
        if (l_Dt.mon == l_Config.excluded_months[i]) return(false);
    }

    // Vérification des jours exclus
    //-------------------------------
    for (int i = 0; i < l_Config.nb_excl_days; i++)
    {
        if (l_Dt.day_of_week == l_Config.excluded_days[i]) return(false);
    }

    return(true);
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
        opr_start        = StringToTime(today_str + " 15:30");
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
//| CheckSuperTrend                                                  |
//| Vérifie direction ST (bougie clôturée)                           |
//| INPUT:                                                           |
//|  i_trend : tendance détectée (par référence)                     |
//| OUTPUT:                                                          |
//|  TRUE si on a une tendance de la ST                              |
//+------------------------------------------------------------------+
bool CStrategy::CheckSuperTrend(ENUM_TREND &i_trend)
{
    double st_direction[];

    if (CopyBuffer(m_HandleST_D, 2, 1, 1, st_direction) != 1)
    {
        LOG.WARNING(DATAS.GetStrategyName() + "SuperTrend indisponible", __FUNCTION__);
        return(false);
    }    
    ArraySetAsSeries(st_direction, true);

    if      (st_direction[0] > 0.0) i_trend = eT_Bull;
    else if (st_direction[0] < 0.0) i_trend = eT_Bear;
    else                            return(false);

    return(true);
}

//+------------------------------------------------------------------+
//| CheckEMA                                                         |
//| Vérifie EMA20 vs EMA50 (bougie clôturée)                         |
//| INPUT:                                                           |
//|  i_trend : tendance détectée (par référence)                     |
//| OUTPUT:                                                          |
//|  TRUE si on a une tendance sur les EMAs                          |
//+------------------------------------------------------------------+
bool CStrategy::CheckEMA(ENUM_TREND &i_trend)
{
    double ema20[];
    double ema50[];

    if (CopyBuffer(m_HandleEMA20_M5, 0, 1, 1, ema20) != 1)
    {
        LOG.WARNING(DATAS.GetStrategyName() + "EMA20 indisponible", __FUNCTION__);
        return(false);
    }    
    if (CopyBuffer(m_HandleEMA50_M5, 0, 1, 1, ema50) != 1)
    {
        LOG.WARNING(DATAS.GetStrategyName() + "EMA50 indisponible", __FUNCTION__);
        return(false);
    }    
    ArraySetAsSeries(ema20, true);
    ArraySetAsSeries(ema50, true);

    if      (ema20[0] > ema50[0]) i_trend = eT_Bull;
    else if (ema20[0] < ema50[0]) i_trend = eT_Bear;
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
    STRUCT_SYMBOL_CONFIG l_Config = GetSymbolConfig(I_Symbol_Key);
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
        double be_ratio = (K_BE_Override > 0) ? K_BE_Override : l_Config.breakeven_r;
        if (l_Ratio < be_ratio) continue;
        
        l_Update = false;
        l_Spread = i_tick.ask - i_tick.bid;
        l_Buffer = l_Config.buffer_be * l_Point;
                    
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