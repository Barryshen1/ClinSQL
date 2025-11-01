WITH base_patients AS (
  SELECT subject_id, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 78 AND 88
),
icu_hadms AS (
  SELECT DISTINCT s.subject_id, s.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN base_patients bp ON s.subject_id = bp.subject_id
),
hhs_hadms AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN icu_hadms ih ON di.subject_id = ih.subject_id AND di.hadm_id = ih.hadm_id
  WHERE (di.icd_version = 9 AND di.icd_code LIKE '250.2%')
     OR (di.icd_version = 10 AND di.icd_code LIKE 'E11.0%')
),
admissions AS (
  SELECT 
    a.hadm_id, 
    a.subject_id, 
    a.hospital_expire_flag, 
    bp.anchor_age,
    CASE WHEN hh.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_hhs
  FROM icu_hadms ih
  JOIN base_patients bp ON ih.subject_id = bp.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON ih.hadm_id = a.hadm_id
  LEFT JOIN hhs_hadms hh ON ih.hadm_id = hh.hadm_id
),
first_stays AS (
  SELECT hadm_id, stay_id, intime
  FROM (
    SELECT hadm_id, stay_id, intime,
           ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    WHERE hadm_id IN (SELECT hadm_id FROM admissions)
  ) 
  WHERE rn = 1
),
total_icu_los AS (
  SELECT hadm_id, SUM(los) AS icu_los
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE hadm_id IN (SELECT hadm_id FROM admissions)
  GROUP BY hadm_id
),
base AS (
  SELECT 
    a.hadm_id, a.subject_id, a.hospital_expire_flag, a.anchor_age, a.is_hhs,
    fs.stay_id, fs.intime,
    tl.icu_los
  FROM admissions a
  JOIN first_stays fs ON a.hadm_id = fs.hadm_id
  JOIN total_icu_los tl ON a.hadm_id = tl.hadm_id
),
vital_items AS (
  SELECT itemid, lownormalvalue AS low, highnormalvalue AS high
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE category = 'Vital Signs' 
    AND lownormalvalue IS NOT NULL 
    AND highnormalvalue IS NOT NULL
),
abnormal_counts AS (
  SELECT 
    ce.stay_id,
    COUNT(*) AS total_vitals,
    SUM(CASE 
      WHEN ce.valuenum < vi.low OR ce.valuenum > vi.high THEN 1 
      ELSE 0 
    END) AS total_abnormal
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN vital_items vi ON ce.itemid = vi.itemid
  JOIN base b ON ce.stay_id = b.stay_id
  WHERE ce.charttime >= b.intime
    AND ce.charttime < DATETIME_ADD(b.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
),
final_scores AS (
  SELECT 
    b.hadm_id,
    b.is_hhs,
    b.hospital_expire_flag,
    b.icu_los,
    COALESCE(ac.total_abnormal, 0) AS total_abnormal,
    COALESCE(ac.total_vitals, 0) AS total_vitals,
    CASE 
      WHEN COALESCE(ac.total_vitals, 0) > 0 
      THEN COALESCE(ac.total_abnormal, 0) * 1.0 / ac.total_vitals 
      ELSE 0 
    END AS abnormal_vital_burden,
    COALESCE(ac.total_abnormal, 0) * 1.0 / 48 AS instability_score
  FROM base b
  LEFT JOIN abnormal_counts ac ON b.stay_id = ac.stay_id
)
SELECT 
  is_hhs,
  -- Percentiles for instability score
  APPROX_QUANTILES(instability_score, 4)[OFFSET(1)] AS instability_25th,
  APPROX_QUANTILES(instability_score, 4)[OFFSET(2)] AS instability_median,
  APPROX_QUANTILES(instability_score, 4)[OFFSET(3)] AS instability_75th,
  -- Mean for abnormal-vital burden
  AVG(abnormal_vital_burden) AS mean_abnormal_vital_burden,
  -- Means for LOS and mortality
  AVG(icu_los) AS mean_icu_los,
  AVG(hospital_expire_flag * 1.0) AS mortality
FROM final_scores
GROUP BY is_hhs
ORDER BY is_hhs;