#property once
//+------------------------------------------------------------------+
//| DST.mqh                                                          |
//| Configuration NASDAQ uniquement                                  |
//|                                                                  |
//| Session US : heures MT5 fixes toute l'année car 5ers et NYSE     |
//| partagent le même DST américain — compensation parfaite.         |
//| OPR Start=16:30 | Session=16:45 | End=18:30 | Close=22:00        |
//+------------------------------------------------------------------+
enum ENUM_MARKET
{
    eM_US     = 0,   // Marchés US (NYSE/NASDAQ)
    eM_EU     = 1,   // Marchés EURO (DAX/EU50)
    eM_Nikkei = 2,   // Nikkei (TSE Tokyo)
};

//+------------------------------------------------------------------+
//| ENUM_SYMBOL_KEY                                                  |
//| Clé de l'actif — détermine toute la configuration en interne     |
//+------------------------------------------------------------------+
enum ENUM_SYMBOL_KEY
{
    eSK_NASDAQ    = 0,   // NAS100USD — Nasdaq 100
};

//+------------------------------------------------------------------+
//| STRUCT_SYMBOL_CONFIG                                             |
//| Configuration complète d'un actif                                |
//+------------------------------------------------------------------+
struct STRUCT_SYMBOL_CONFIG
{
    // Marché et DST
    //--------------
    ENUM_MARKET market;

    // Paramètres de stratégie OPR (source : backtest 20 ans)
    //--------------------------------------------------------
    double      risk_reward;      // Ratio Risk/Reward (colonne TP)
    double      offset_points;    // Buffer anti fausse cassure — TODO optimisation
    bool        apply_be;         // Activer le BreakEven ?
    double      breakeven_r;      // Ratio R pour déclencher le BE (colonne BE)
    double      buffer_be;        // Buffer BE en points — TODO optimisation

    // Filtres de session
    //--------------------
    // Conventions :
    //  excluded_months : numéro du mois (1=jan ... 12=dec)
    //  excluded_days   : 0=dim, 1=lun, 2=mar, 3=mer, 4=jeu, 5=ven, 6=sam
    //--------------------
    int         excluded_months[4];
    int         nb_excl_months;
    int         excluded_days[4];
    int         nb_excl_days;
};

//+------------------------------------------------------------------+
//| GetSymbolConfig                                                  |
//| Retourne la configuration complète d'un actif                    |
//|                                                                  |
//| Sources :                                                        |
//|  ✅ risk_reward, apply_be, breakeven_r                            |
//|  ⚠️  offset_points, buffer_be                                    |
//|                                                                  |
//| Conventions excluded_days :                                      |
//|  0=dim, 1=lun, 2=mar, 3=mer, 4=jeu, 5=ven, 6=sam                 |
//|                                                                  |
//| INPUT:                                                           |
//|  i_key : clé de l'actif (ENUM_SYMBOL_KEY)                        |
//| OUTPUT:                                                          |
//|  STRUCT_SYMBOL_CONFIG remplie                                    |
//+------------------------------------------------------------------+
STRUCT_SYMBOL_CONFIG GetSymbolConfig(const ENUM_SYMBOL_KEY i_key)
{
    STRUCT_SYMBOL_CONFIG l_Config;
    ZeroMemory(l_Config);
    
    // NASDAQ — valeurs surchargées par K_TP_Override et K_BE_Override
    //-----------------------------------------------------------------
    l_Config.risk_reward    = 1.0;
    l_Config.offset_points  = 1.0;
    l_Config.apply_be       = true;
    l_Config.breakeven_r    = 0.25;
    l_Config.buffer_be      = 2.0;
    
    return(l_Config);
}