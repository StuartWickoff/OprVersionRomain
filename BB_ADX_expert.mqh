//+---------------------------------------------------------------+
//| Corps du robot avec centralisation des opérations             |
//|                                                               |
//| (Le code est compatible MT4/MT5)                              |
//|                                                               |
//+---------------------------------------------------------------+
//|                                                               |
//| 
//|                                                               |
//+---------------------------------------------------------------+
//|                                                               |
//| TODO avec Grok : Liste des fonctions et leur rôle             |
//|
//+---------------------------------------------------------------+
//| Dépendances :
//| - Fichier Tools.mqh         : Contient les fonctions de mise
//|                               en forme
//| - Fichier Type.mqh          : Contient les constantes et les 
//|                               types généraux
//| - Fichier Log.mqh           : Contient la gestion des logs
//|
//| - Fichier Alert.mqh         : Contient la gestion des alertes
//|
//| - Fichier Parameters.mqh    : Contient la gestion des paramètres
//|
//|
//|
//+---------------------------------------------------------------+

//////////////////////////////////////////////////////////
//                                                      //
//              C O N S T A N T E S                     //
//                                                      //
//////////////////////////////////////////////////////////
#define K_Magic               1000000               // Magic number :  avec N° du bot
#define K_Repertory           "Bot_OPR\\"
#define K_SoftName            "BotOPR_001"
#define K_AlertSoundName      "alert.wav"
#define K_Cyclic              1                     // Traitement cyclique toutes les secondes


//////////////////////////////////////////////////////////
//                                                      //
//              I N C L U D E S                         //
//                                                      //
//////////////////////////////////////////////////////////
#include <BB_ADX_EXPERT/Type.mqh>
#include <BB_ADX_EXPERT/DST.mqh>
#include <BB_ADX_EXPERT/Tools.mqh>
#include <BB_ADX_EXPERT/Log.mqh>
#include <BB_ADX_EXPERT/Alert.mqh>
#include <BB_ADX_EXPERT/Parameters.mqh>
#include <BB_ADX_EXPERT/Context.mqh>
#include <BB_ADX_EXPERT/Money.mqh>
#include <BB_ADX_EXPERT/Visu.mqh>
#include <BB_ADX_EXPERT/Monitoring.mqh>
#include <BB_ADX_EXPERT/Broker.mqh>
#include <BB_ADX_EXPERT/Strategy.mqh>


//////////////////////////////////////////////////////////
//                                                      //
//                   D A T A S                          //
//                                                      //
//////////////////////////////////////////////////////////

//============================================
//---  User parameters
//============================================
input uint                I_TAILLE_DU_COMPTE     = 25000;          // Taille du compte de trading (balance initiale)
enum ENUM_BALANCE_MODE
{
    eBM_Fixed    ,  // Balance fixe (intérêts simples)
    eBM_Compound ,  // Balance réelle du compte (intérêts composés)
};
input ENUM_BALANCE_MODE K_BalanceMode            = eBM_Compound;     // Mode de calcul du risque
input uint                I_Robot_ID             = 0;             // ID unique du robot sur MetaTrader
input bool                I_Text_Alert           = true;          // Alerte texte écran
input bool                I_Sound_Alert          = true;          // Alerte sonore
input bool                I_Notif_Alert          = true;          // Alerte notification
input ENUM_LOG_LEVEL      I_Log_Level            = eL_All;        // Niveau des logs
input ENUM_VISU           I_Visu_Height          = eV_Nothing;    // Taille affichage états
input uint                I_Deviation            = 10;            // Slippage autorisé
input string              I_Symbol_Name          = "US100m";      // Symbole exact dans MT5
input ENUM_SYMBOL_KEY     I_Symbol_Key           = eSK_NASDAQ;    // Actif tradé
enum ENUM_SL_TYPE
{
    eSL_Mid          ,  // Milieu du range
    eSL_LowHigh      ,  // Low/High de la range
    eSL_LowHighBuffer,  // Low/High + buffer
};

input ENUM_SL_TYPE        K_SL_Type              = eSL_LowHigh;  // Type de Stop Loss
input double              K_SL_Buffer_Ratio      = 0.10;         // Buffer SL (% de la range)
input ENUM_TIMEFRAMES     K_ORB_TF               = PERIOD_M15;   // Timeframe bougie ORB
input double              K_TP_Override          = 0.0;          // TP désactivé dans cette version
input double              K_BE_Override          = 0.25;         // BE ratio
input double              K_MaxSlippage_Points   = 5.0;         // Slippage max accepté pour bascule marché (pts)
input double              K_MinRange_ATR_Ratio   = 0.5;          // Range min = X × ATR(14)
input ENUM_APPLIED_PRICE  K_ST_Source            = PRICE_MEDIAN;
input uint                I_ST_Plateau_MinCount  = 3;            // n = Nombre minimum d'occurrences pour confirmer plateau
input double              K_Max_Risk_Auth        = 2.5;          // Risque max autorisé pour fallback MinLot (%)

// Mode de gestion du Stop Loss après l'entrée ORB.
//   SL_MODE_R_BE       : ancien mode BreakEven par ratio R (ApplyBreakEven)
//   SL_MODE_ST_PLATEAU : nouveau mode protection par plateaux SuperTrend M1
// Les deux modes NE doivent JAMAIS tourner simultanément sur la même position.
enum ENUM_SL_MANAGEMENT_MODE
{
   SL_MODE_R_BE        = 0,   // BreakEven par ratio R (ancien)
   SL_MODE_ST_PLATEAU  = 1,   // Plateaux SuperTrend M1 (nouveau)
};
input ENUM_SL_MANAGEMENT_MODE I_SL_Management_Mode = SL_MODE_ST_PLATEAU; // Mode de gestion du SL post-entrée
 

//============================================
//---   Variables globales
//============================================
int   G_DeInit = -1;

//============================================
//---   objects
//============================================
CLog              LOG;
CAlert            ALERT;
CParameters       PARAM;
CContext          CONTEXT;
CMoney            MONEY;
CVisu             VISU;
CMonitoring       MONITORING;
CBroker           BROKER;
CStrategy         STRAT;


////////////////////////////////////////////////////////////////////
///                                                              ///
///             ###  #   #    ### #   # ### #####                ///
///            #   # ##  #     #  ##  #  #    #                  ///
///            #   # # # #     #  # # #  #    #                  ///
///            #   # #  ##     #  #  ##  #    #                  ///
///             ###  #   #    ### #   # ###   #                  ///
///                                                              ///
////////////////////////////////////////////////////////////////////
int OnInit(void)
{   
   // Variable locale
   //----------------
   bool l_CorrectInit;

   // Initialise le système de log
   //-----------------------------
   l_CorrectInit = LOG.Config(K_Repertory);
   LOG.SetLevel(I_Log_Level);
   
   // Initialise le système d'alerte
   //-------------------------------
   ALERT.Config(K_SoftName, K_AlertSoundName);
   ALERT.AlertType(I_Text_Alert, I_Sound_Alert, I_Notif_Alert);

   // Initialise les données pour le contrôle budgétaire
   //---------------------------------------------------
   MONEY.Config();
   MONEY.SetMaxRiskAuth(K_Max_Risk_Auth);

   // Initialise le contrôle du contexte
   //-----------------------------------
   CONTEXT.Config();
   
   // Initialise le système de paramètres
   //------------------------------------
   l_CorrectInit &= PARAM.Config(K_Repertory);  //--- Similaire à i += 1

   // Initialise le système d'affichage
   //----------------------------------
   VISU.Config(IntegerToString(K_Magic), I_Visu_Height);

   // Initialise le système de surveillance
   //--------------------------------------
   MONITORING.Config();

   // Initialisation de la stratégie
   //-------------------------------
   l_CorrectInit &= STRAT.Config("StrategyTest", PERIOD_CURRENT, K_Repertory);
   
   // Validation du contexte
   //-----------------------
   if (!l_CorrectInit || (G_DeInit != REASON_CHARTCHANGE))
   {
      if (!ContextValidation(l_CorrectInit))
      {
         return(INIT_FAILED);
      }
   }

   // Tentative d'initialisation des traitements cycliques
   //-----------------------------------------------------
   if (!MQLInfoInteger(MQL_TESTER))
   {
      ResetLastError();
      if (!EventSetTimer(K_Cyclic))
      {
         LOG.ERROR_CODE(GetLastError(), __FUNCTION__);
         return(INIT_FAILED);
      }
   }

   // Lancement du premier traitement général pour vérifier que tout est correct
   //---------------------------------------------------------------------------
   if (!RegularTreatments())
   {
      Alert("Absence de fichier 'Param.dta', exécution impossible !");
      LOG.ERROR("Absence de fichier 'Param.dta', exécution impossible !", __FUNCTION__);
      return(INIT_FAILED);
   }
   
   // Retour sans erreur
   //-------------------
   return(INIT_SUCCEEDED);
}

////////////////////////////////////////////////////////////////////
///                                                              ///
///          ###  #   #    ####  #### ### #   # ### #####        ///
///         #   # ##  #    #   # #     #  ##  #  #    #          ///
///         #   # # # #    #   # ###   #  # # #  #    #          ///
///         #   # #  ##    #   # #     #  #  ##  #    #          ///
///          ###  #   #    ####  #### ### #   # ###   #          ///
///                                                              ///
////////////////////////////////////////////////////////////////////
void OnDeinit(const int reason)
{
   EventKillTimer();
   LOG.End();
   STRAT.End();
   VISU.End();
   G_DeInit = reason;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
///                                                                                              ///
///          ###  #   #     ###  #   #  ###  ####  #####    ##### #     # ##### #   # #####      ///
///         #   # ##  #    #   # #   # #   # #   #   #      #     #     # #     ##  #   #        ///
///         #   # # # #    #     ##### ##### ####    #      ###    #   #  ###   # # #   #        /// 
///         #   # #  ##    #   # #   # #   # #  #    #      #       # #   #     #  ##   #        ///
///          ###  #   #     ###  #   # #   # #   #   #      #####    #    ##### #   #   #        ///
///                                                                                              ///
////////////////////////////////////////////////////////////////////////////////////////////////////
void OnChartEvent(const int      id,          // Event ID
                  const long&    lparam,      // Parameter of type long event
                  const double&  dparam,      // Parameter of type double event
                  const string&  sparam)      // Parameter of type string event
{
   // Variable locale
   //----------------
   ENUM_CHART_EVENT l_Event;                  // Evénement graphique

   // Traduit en type réel
   //---------------------
   l_Event = (ENUM_CHART_EVENT)id;
   
   // Traitement si l'affichage change
   //---------------------------------
   if (l_Event == CHARTEVENT_CHART_CHANGE)
   {
      // Mise à jour de l'affichage
      //---------------------------
      VISU.ReDraw();
   }
}

////////////////////////////////////////////////////////////////////
///                                                              ///
///             ###  #   #    ##### ### #   # #### ####          ///
///            #   # ##  #      #    #  ## ## #    #   #         ///
///            #   # # # #      #    #  # # # ###  ####          ///
///            #   # #  ##      #    #  #   # #    #  #          ///
///             ###  #   #      #   ### #   # #### #   #         ///
///                                                              ///
////////////////////////////////////////////////////////////////////
void OnTimer()
{
   // Effectue les traitements à faire régulièrement
   //-----------------------------------------------
   RegularTreatments();

   // ✅ ManagePositions toujours appelé : la zone NEWS est gérée EN INTERNAL
   // (annulation pending + gestion position existante + protection SL plateau).
   // ReadyForStrategy ne filtre QUE les nouvelles entrées (Detection).
   //------------------------------------------------------------------------
   STRAT.ManagePositions();
}

////////////////////////////////////////////////////////////////////
///                                                              ///
///             ###  #   #    ##### ###  ### #   #               ///
///            #   # ##  #      #    #  #    #  #                ///
///            #   # # # #      #    #  #    ###                 ///
///            #   # #  ##      #    #  #    #  #                ///
///             ###  #   #      #   ###  ### #   #               ///
///                                                              ///
////////////////////////////////////////////////////////////////////
void OnTick()
{
   // Effectue les traitements à faire régulièrement
   //-----------------------------------------------
   RegularTreatments();

   // ✅ ManagePositions toujours appelé (même en zone NEWS) :
   //    - annulation pending orders en zone NEWS
   //    - sortie EMA M1 reste active
   //    - protection SL par plateaux ST M1 reste active
   // La zone NEWS ne bloque QUE les nouvelles entrées (Detection ci-dessous).
   //-------------------------------------------------------------------------
   STRAT.ManagePositions();

   // Traite la détection de nouvelles opportunités uniquement si tous les
   // contextes (technique, finance, horaire, hors news) sont réunis.
   //--------------------------------------------------------------------
   if (!MONITORING.ReadyForStrategy()) return;

   if (CONTEXT.NewCandle())
   {
      STRAT.Detection();
   }
}

/////////////////////////////////////////////////////////////////////
//                                                                 //
//       ##### #   # #   #  ###  ##### ###  ###  #   #  ####       //
//       #     #   # ##  # #   #   #    #  #   # ##  # #           //
//  ###  ###   #   # # # # #       #    #  #   # # # #  ###    ### //
//       #     #   # #  ## #   #   #    #  #   # #  ##     #       //
//       #      ###  #   #  ###    #   ###  ###  #   # ####        //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//+--------------------------------------------------------------------+
//| ContextValidation                                                  |
//| Récupère les infos des objets LOG et PARAM pour les valider        |
//| INPUT:                                                             |
//|  TRUE si les initialisations ont été faites sans erreur            |
//| OUTPUT:                                                            |
//|  TRUE si le contexte est validé                                    |
//+--------------------------------------------------------------------+
bool ContextValidation(const bool i_initResult)
{
   // Variable locale
   //----------------
   string   l_Text;
   int      l_FlagMessageBox;
   int      l_ResponseMessageBox;

   // Pour mémorisation dans les logs MetaTrader
   //-------------------------------------------
   Print(LOG.GetFolder());
   Print(PARAM.GetFileName());
   
   // Informations sur le contexte
   //-----------------------------
   l_Text               = LOG.GetFolder() + "\n\n";
   l_Text              += PARAM.GetFileName() + "\n\n";
   l_Text              += (STRAT.ConfigOk()) ? " Stratégie correctement initialisée.\n" :
                                               " Stratégie mal configurée.\n";
   l_Text              += (i_initResult) ? "" :
                                           "\nDoit-on continuer ?\n";
   l_FlagMessageBox     = (i_initResult) ? MB_OK | MB_ICONINFORMATION | MB_DEFBUTTON1 :
                                           MB_YESNO | MB_ICONQUESTION | MB_DEFBUTTON2;
   l_ResponseMessageBox = MessageBox(l_Text, "Infos de démarrage", l_FlagMessageBox);
   
   if (l_ResponseMessageBox == IDNO)
   {
      return(false);
   }
   
   // Contexte valide
   //----------------
   return(true);
                                             
}

/*
ParametersExtraction
Extrait les paramètres et configure les différentes fonctions
(Pour les LOG et ALERTE, c'est directement dans les param.)
(Tous les paramètres temporels sont dans les paramètres)
INPUT
*/
void ParametersExtraction(void)
{
   // Variable locale
   //----------------
   double l_DoubleValue;
   int    l_IntValue;
   
   // Renseigne les paramètres de money management
   //---------------------------------------------
   MONEY.Config();
   MONEY.SetMaxRiskAuth(K_Max_Risk_Auth);   
   if (PARAM.GetRiskLevel(l_DoubleValue))       MONEY.SetRisk(l_DoubleValue);
   if (PARAM.GetMaxDayLoss(l_DoubleValue))      MONEY.SetDailyMaxLoss(l_DoubleValue);
   if (PARAM.GetMaxWeekLoss(l_DoubleValue))     MONEY.SetWeeklyMaxLoss(l_DoubleValue);
   if (PARAM.GetTrailingStop(l_DoubleValue))    MONEY.SetTrailingStop(l_DoubleValue);

   // Renseigne les paramètres de contexte
   //-------------------------------------
   CONTEXT.SetRun(PARAM.RobotIsRun());
   CONTEXT.SetSimulation(PARAM.RobotInSimulation());

   // Renseigne les paramètres d'affichage
   //-------------------------------------
   if (PARAM.GetVisuHeight(l_IntValue))      VISU.SetHeight(l_IntValue);
}
/*
RegularTreatments
Que ce soit en cycle ou à chaque événement sur le marché
INPUT:
None
OUTPUT:
TRUE si le traitement n'a pas d'erreur bloquante
*/
bool RegularTreatments(void)
{
   // Gère la lecture des paramètres
   //-------------------------------
   if (PARAM.CyclicFileAnalysis())
   {
      // Extraction des paramètres
      //--------------------------
      ParametersExtraction();
   }

   // Met à jour les états de contexte
   //---------------------------------
   CONTEXT.Cyclic();

   // Met à jour les données monétaires
   //----------------------------------
   MONEY.Cyclic();

   // Fait une surveillance cyclique
   //-------------------------------
   MONITORING.Cyclic();

   // Gère la fin des positions ouvertes
   //-----------------------------------
   STRAT.DeleteDetection();

   // Retourne l'information des paramètres lus au moins une fois
   // Situation bloquante avec le robot ' à poil' !
   //------------------------------------------------------------
   return(PARAM.ParametersRead());
   
}
