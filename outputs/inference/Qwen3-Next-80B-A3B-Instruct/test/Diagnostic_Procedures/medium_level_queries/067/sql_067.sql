WITH eligible_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.gender,
    p.anchor_age,
    di.seq_num AS acs_seq_num
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic ON di.icd_code = dic.icd_code AND di.icd_version = dic.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
    AND (
      dic.long_title LIKE '%acute coronary syndrome%'
      OR dic.long_title LIKE '%myocardial infarction%'
      OR dic.long_title LIKE '%unstable angina%'
    )
),
icu_stay_counts AS (
  SELECT 
    hadm_id,
    COUNT(stay_id) AS num_icu_stays
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
echo_ultrasound_procedures AS (
  SELECT 
    pe.hadm_id,
    COUNT(*) AS num_echo_ultrasound
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE 
    LOWER(di.label) LIKE '%echo%'
    OR LOWER(di.label) LIKE '%ultrasound%'
    OR LOWER(di.label) LIKE '%echocardiogram%'
  GROUP BY pe.hadm_id
),
combined AS (
  SELECT 
    ea.hadm_id,
    ea.los_days,
    ea.acs_seq_num,
    COALESCE(isc.num_icu_stays, 0) AS num_icu_stays,
    COALESCE(eup.num_echo_ultrasound, 0) AS num_echo_ultrasound
  FROM eligible_admissions ea
  LEFT JOIN icu_stay_counts isc ON ea.hadm_id = isc.hadm_id
  LEFT JOIN echo_ultrasound_procedures eup ON ea.hadm_id = eup.hadm_id
)
SELECT
  CASE 
    WHEN num_icu_stays BETWEEN 1 AND 4 THEN '1-4 stays'
    WHEN num_icu_stays BETWEEN 5 AND 7 THEN '5-7 stays'
  END AS icu_stay_stratum,
  CASE 
    WHEN acs_seq_num = 1 THEN 'Primary ACS'
    WHEN acs_seq_num > 1 THEN 'Secondary ACS'
  END AS acs_type,
  PERCENTILE_CONT(num_echo_ultrasound, 0.25) AS p25,
  PERCENTILE_CONT(num_echo_ultrasound, 0.50) AS p50,
  PERCENTILE_CONT(num_echo_ultrasound, 0.75) AS p75
FROM combined
WHERE num_icu_stays BETWEEN 1 AND 7
GROUP BY icu_stay_stratum, acs_type
ORDER BY icu_stay_stratum, acs_type;