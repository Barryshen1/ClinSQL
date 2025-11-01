WITH ich_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
    ON di.icd_code = ddi.icd_code
    AND di.icd_version = ddi.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    AND LOWER(ddi.long_title) LIKE '%intracerebral hemorrhage%'
),
labs_48h AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT le.itemid) AS instability_score
  FROM ich_cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.subject_id = le.subject_id
    AND c.hadm_id = le.hadm_id
    AND le.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
  WHERE le.itemid IS NOT NULL
    AND (
      LOWER(le.flag) = 'abnormal'
      OR (le.valuenum IS NOT NULL AND (
           (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower) OR
           (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
         ))
    )
  GROUP BY c.subject_id, c.hadm_id
),
cohort_with_score AS (
  SELECT
    c.*,
    IFNULL(l.instability_score, 0) AS instability_score,
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days
  FROM ich_cohort c
  LEFT JOIN labs_48h l
    ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id
),
quartiled AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY instability_score) AS quartile
  FROM cohort_with_score
)
-- First result: quartile stats
SELECT
  quartile,
  COUNT(*) AS admissions_count,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(AVG(hospital_expire_flag)*100, 2) AS mortality_rate_percent
FROM quartiled
GROUP BY quartile
ORDER BY quartile;

-- Second result: compare ICH vs all inpatients mean instability score
WITH all_inpatient_scores AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNT(DISTINCT le.itemid) AS instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON a.subject_id = le.subject_id
    AND a.hadm_id = le.hadm_id
    AND le.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 48 HOUR)
  WHERE le.itemid IS NOT NULL
    AND (
      LOWER(le.flag) = 'abnormal'
      OR (le.valuenum IS NOT NULL AND (
           (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower) OR
           (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
         ))
    )
  GROUP BY a.subject_id, a.hadm_id
),
cohort_with_score AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    IFNULL(l.instability_score, 0) AS instability_score
  FROM (
    SELECT
      p.subject_id,
      a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON a.hadm_id = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
      ON di.icd_code = ddi.icd_code
      AND di.icd_version = ddi.icd_version
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 73 AND 83
      AND LOWER(ddi.long_title) LIKE '%intracerebral hemorrhage%'
  ) c
  LEFT JOIN all_inpatient_scores l
    ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id
),
ich_mean_score AS (
  SELECT AVG(instability_score) AS mean_score
  FROM cohort_with_score
),
all_mean_score AS (
  SELECT AVG(instability_score) AS mean_score
  FROM all_inpatient_scores
)
SELECT 'ICH cohort' AS group_label, mean_score FROM ich_mean_score
UNION ALL
SELECT 'All inpatients' AS group_label, mean_score FROM all_mean_score;