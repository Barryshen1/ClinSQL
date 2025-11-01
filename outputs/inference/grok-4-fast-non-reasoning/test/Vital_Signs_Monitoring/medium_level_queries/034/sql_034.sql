WITH niv_stays AS (
  -- Identify ICU stays with any NIV usage
  SELECT DISTINCT icu.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce_niv
    ON icu.subject_id = ce_niv.subject_id
    AND icu.hadm_id = ce_niv.hadm_id
    AND icu.stay_id = ce_niv.stay_id
    AND ce_niv.charttime BETWEEN icu.intime AND icu.outtime
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di_niv
    ON ce_niv.itemid = di_niv.itemid
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 37 AND 47
    AND icu.los > 0
    AND di_niv.itemid IN (223848, 223849, 223850)  -- NIV, CPAP, BiPAP
    AND ce_niv.value IS NOT NULL
    AND ce_niv.value != 'Off'
),
dbp_per_stay AS (
  -- Compute max diastolic BP per qualifying NIV stay
  SELECT 
    ns.stay_id,
    MAX(ce_dbp.valuenum) AS max_dbp
  FROM niv_stays ns
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ns.stay_id = icu.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce_dbp
    ON icu.subject_id = ce_dbp.subject_id
    AND icu.hadm_id = ce_dbp.hadm_id
    AND icu.stay_id = ce_dbp.stay_id
    AND ce_dbp.charttime BETWEEN icu.intime AND icu.outtime
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di_dbp
    ON ce_dbp.itemid = di_dbp.itemid
  WHERE di_dbp.itemid = 2202  -- Non-Invasive Blood Pressure diastolic
    AND ce_dbp.valuenum IS NOT NULL
  GROUP BY ns.stay_id
)
-- Compute 25th percentile of max DBP across stays
SELECT 
  PERCENTILE_CONT(max_dbp, 0.25) AS p25_max_dbp
FROM dbp_per_stay;