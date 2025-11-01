WITH ugib_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%gastrointest%bleed%'
    OR (icd_version = 10 AND icd_code IN ('K920', 'K921', 'K922'))
    OR (icd_version = 9 AND icd_code IN ('5780', '5781', '5789'))
),
ugib_admissions AS (
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN ugib_codes u
    ON di.icd_code = u.icd_code AND di.icd_version = u.icd_version
  GROUP BY di.hadm_id
),
eligible_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
),
icu_stays_with_ugib AS (
  SELECT ie.subject_id, ie.hadm_id, ie.stay_id, ie.intime, ie.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN ugib_admissions ua ON ie.hadm_id = ua.hadm_id
  INNER JOIN eligible_patients ep ON ie.subject_id = ep.subject_id
),
procedure_counts_24h AS (
  SELECT 
    iwu.stay_id,
    iwu.hadm_id,
    COUNT(pe.stay_id) AS procedure_count_24h
  FROM icu_stays_with_ugib iwu
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON iwu.stay_id = pe.stay_id
    AND pe.starttime >= iwu.intime
    AND pe.starttime < DATETIME_ADD(iwu.intime, INTERVAL 24 HOUR)
    AND pe.starttime IS NOT NULL
  GROUP BY iwu.stay_id, iwu.hadm_id
),
quintiles AS (
  SELECT 
    stay_id,
    hadm_id,
    procedure_count_24h,
    NTILE(5) OVER (ORDER BY procedure_count_24h) AS quintile
  FROM procedure_counts_24h
)
SELECT
  q.quintile,
  AVG(q.procedure_count_24h) AS avg_procedures,
  AVG(DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0) AS avg_hospital_los_days,
  AVG(a.hospital_expire_flag) AS in_hospital_mortality_rate
FROM quintiles q
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON q.hadm_id = a.hadm_id
GROUP BY q.quintile
ORDER BY q.quintile;