WITH pe_patients AS (
  SELECT DISTINCT p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, 
         TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 74 AND 84
    AND d_icd.long_title LIKE '%pulmonary embolism%'
),

medications_first_24h AS (
  SELECT p.subject_id, p.hadm_id, p.starttime,
         CASE 
           WHEN LOWER(p.drug) LIKE '%amiodarone%' 
                OR LOWER(p.drug) LIKE '%ciprofloxacin%' 
                OR LOWER(p.drug) LIKE '%levofloxacin%' 
                OR LOWER(p.drug) LIKE '%fluconazole%' 
                OR LOWER(p.drug) LIKE '%macrolide%' 
                OR LOWER(p.drug) LIKE '%sotalol%' 
                OR LOWER(p.drug) LIKE '%quinidine%' 
                OR LOWER(p.drug) LIKE '%chloroquine%' 
                OR LOWER(p.drug) LIKE '%haloperidol%' 
                OR LOWER(p.drug) LIKE '%thioridazine%' 
                OR LOWER(p.drug) LIKE '%cisapride%' 
                OR LOWER(p.drug) LIKE '%methadone%' 
           THEN 1 ELSE 0 END AS qt_prolonging,
         CASE 
           WHEN LOWER(p.drug) LIKE '%warfarin%' 
                OR LOWER(p.drug) LIKE '%heparin%' 
                OR LOWER(p.drug) LIKE '%enoxaparin%' 
                OR LOWER(p.drug) LIKE '%clopidogrel%' 
                OR LOWER(p.drug) LIKE '%aspirin%' 
                OR LOWER(p.drug) LIKE '%ticagrelor%' 
                OR LOWER(p.drug) LIKE '%dabigatran%' 
                OR LOWER(p.drug) LIKE '%rivaroxaban%' 
                OR LOWER(p.drug) LIKE '%apixaban%' 
                OR LOWER(p.drug) LIKE '%edoxaban%' 
                OR LOWER(p.drug) LIKE '%tirofiban%' 
                OR LOWER(p.drug) LIKE '%abciximab%' 
           THEN 1 ELSE 0 END AS bleeding_risk
  FROM physionet-data.mimiciv_3_1_hosp.prescriptions p
  JOIN pe_patients pe ON p.subject_id = pe.subject_id AND p.hadm_id = pe.hadm_id
  WHERE p.starttime >= pe.admittime 
    AND p.starttime <= pe.admittime + INTERVAL 24 HOUR
),

icu_status AS (
  SELECT DISTINCT subject_id, hadm_id, 
         CASE WHEN stay_id IS NOT NULL THEN 1 ELSE 0 END AS in_icu
  FROM physionet-data.mimiciv_3_1_icu.icustays
),

medication_complexity AS (
  SELECT 
    m.subject_id,
    m.hadm_id,
    COUNT(*) AS total_medications,
    MAX(m.qt_prolonging) AS has_qt_prolonging,
    MAX(m.bleeding_risk) AS has_bleeding_risk
  FROM medications_first_24h m
  GROUP BY m.subject_id, m.hadm_id
),

final_metrics AS (
  SELECT 
    icu.in_icu,
    AVG(mc.total_medications) AS mean_medication_count,
    MIN(mc.total_medications) AS min_medication_count,
    MAX(mc.total_medications) AS max_medication_count,
    STDDEV_SAMP(mc.total_medications) AS sd_medication_count,
    PERCENTILE_CONT(mc.total_medications, 0.75) OVER () AS p75_medication_count,
    AVG(mc.has_qt_prolonging) AS prevalence_qt_prolonging,
    AVG(mc.has_bleeding_risk) AS prevalence_bleeding_risk,
    PERCENTILE_CONT(pe.los_days, 0.75) OVER () AS p75_los_days,
    AVG(pe.hospital_expire_flag) AS mortality_rate
  FROM medication_complexity mc
  JOIN pe_patients pe ON mc.subject_id = pe.subject_id AND mc.hadm_id = pe.hadm_id
  LEFT JOIN icu_status icu ON mc.subject_id = icu.subject_id AND mc.hadm_id = icu.hadm_id
  GROUP BY icu.in_icu
)

SELECT 
  in_icu,
  mean_medication_count,
  min_medication_count,
  max_medication_count,
  sd_medication_count,
  p75_medication_count,
  prevalence_qt_prolonging,
  prevalence_bleeding_risk,
  p75_los_days,
  mortality_rate
FROM final_metrics
ORDER BY in_icu;