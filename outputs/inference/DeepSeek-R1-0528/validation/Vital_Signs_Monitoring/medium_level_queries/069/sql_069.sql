WITH cohort AS (
  SELECT 
    icu.subject_id, 
    icu.hadm_id, 
    icu.stay_id,
    icu.intime,  -- Added for efficient time filtering
    pat.anchor_age + (EXTRACT(YEAR FROM icu.intime) - pat.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
),
filtered_cohort AS (
  SELECT *
  FROM cohort
  WHERE age_at_admission BETWEEN 41 AND 51
),
rr_events AS (
  SELECT 
    ce.stay_id,
    ce.valuenum AS rr_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN filtered_cohort fc
    ON ce.stay_id = fc.stay_id
  WHERE ce.itemid = 220210  -- Respiratory rate item ID
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= fc.intime  -- Directly use cohort's intime
    AND ce.charttime < DATETIME_ADD(fc.intime, INTERVAL 48 HOUR)
),
rr_avg AS (
  SELECT 
    stay_id,
    AVG(rr_value) AS avg_rr
  FROM rr_events
  GROUP BY stay_id
),
cohort_with_rr AS (
  SELECT 
    fc.*,
    ra.avg_rr,
    CASE 
      WHEN ra.avg_rr < 12 THEN '<12'
      WHEN ra.avg_rr BETWEEN 12 AND 20 THEN '12-20'
      WHEN ra.avg_rr BETWEEN 21 AND 29 THEN '21-29'
      WHEN ra.avg_rr >= 30 THEN '>=30'
    END AS rr_category
  FROM filtered_cohort fc
  INNER JOIN rr_avg ra
    ON fc.stay_id = ra.stay_id
),
stroke_diagnoses AS (
  SELECT 
    hadm_id,
    1 AS stroke_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code IN ('430', '431', '432', '433', '434', '436')) OR
    (icd_version = 10 AND icd_code IN ('I60', 'I61', 'I62', 'I63', 'I64'))  -- Removed redundant LIKE
  GROUP BY hadm_id
)
SELECT 
  cwr.rr_category,
  COUNT(cwr.stay_id) AS total_stays,
  COUNT(sd.hadm_id) AS stroke_stays  -- Counts non-null hadm_id (i.e., stroke cases)
FROM cohort_with_rr cwr
LEFT JOIN stroke_diagnoses sd
  ON cwr.hadm_id = sd.hadm_id
GROUP BY cwr.rr_category
ORDER BY
  CASE cwr.rr_category
    WHEN '<12' THEN 1
    WHEN '12-20' THEN 2
    WHEN '21-29' THEN 3
    WHEN '>=30' THEN 4
  END;