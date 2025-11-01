WITH
-- Get male patients aged 39-49
male_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 39 AND 49
),

-- Get first ICU stay per admission with DKA diagnosis
dka_stays AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    TIMESTAMP_DIFF(i.outtime, i.intime, HOUR)/24 AS icu_los_days,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN male_patients p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE d.icd_code IN ('E1310', 'E1311') -- DKA ICD-10 codes
  QUALIFY ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY i.intime) = 1 -- First ICU stay per admission
),

-- Count distinct procedures in first 24 hours of ICU stay
procedure_counts AS (
  SELECT
    s.stay_id,
    COUNT(DISTINCT p.itemid) AS procedure_count
  FROM dka_stays s
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p
    ON s.stay_id = p.stay_id
    AND p.starttime BETWEEN s.icu_intime AND TIMESTAMP_ADD(s.icu_intime, INTERVAL 24 HOUR)
  GROUP BY s.stay_id
),

-- Create quintiles based on procedure counts
quintiles AS (
  SELECT
    stay_id,
    procedure_count,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM procedure_counts
)

-- Final aggregation by quintile
SELECT
  quintile,
  COUNT(s.stay_id) AS number_of_stays,
  AVG(procedure_count) AS mean_procedure_count,
  MIN(procedure_count) AS min_procedure_count,
  MAX(procedure_count) AS max_procedure_count,
  AVG(icu_los_days) AS mean_icu_los_days,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(s.stay_id), 1) AS hospital_mortality_percent
FROM quintiles q
JOIN dka_stays s ON q.stay_id = s.stay_id
GROUP BY quintile
ORDER BY quintile;