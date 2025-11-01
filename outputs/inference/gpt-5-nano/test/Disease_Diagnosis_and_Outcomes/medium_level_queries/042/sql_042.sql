WITH eligible AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.discharge_location,
    CASE WHEN a.deathtime IS NOT NULL THEN 1 ELSE 0 END AS died_in_hospital
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 69 AND 79
    AND a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code
       AND di.icd_version = dd.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
              dd.long_title LIKE '%myocardial infarction%'
              OR di.icd_code LIKE 'I21%'
              OR di.icd_code LIKE '410%'
            )
    )
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd2
        ON di2.icd_code = dd2.icd_code
       AND di2.icd_version = dd2.icd_version
      WHERE di2.subject_id = a.subject_id
        AND di2.hadm_id = a.hadm_id
        AND (
              dd2.long_title LIKE '%shock%'
              OR dd2.long_title LIKE '%respiratory failure%'
            )
    )
),

bin AS (
  SELECT
    subject_id,
    hadm_id,
    los_days,
    discharge_location,
    died_in_hospital,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      WHEN los_days >= 8 THEN '8+'
    END AS los_bin
  FROM eligible
  WHERE los_days >= 1  -- include only meaningful LOS bins
),

-- Median LOS per bin (approximate, robust for large counts)
med AS (
  SELECT
    b.los_bin,
    (quantiles)[OFFSET(50)] AS median_los
  FROM (
    SELECT
      los_bin,
      APPROX_QUANTILES(los_days, 100) AS quantiles
    FROM bin
    GROUP BY los_bin
  ) AS q
  JOIN (
    SELECT DISTINCT los_bin FROM bin
  ) AS b ON q.los_bin = b.los_bin
)

SELECT
  b.los_bin,
  b.discharge_location,
  COUNT(*) AS total_admissions,
  SUM(b.died_in_hospital) AS deaths,
  100.0 * SUM(b.died_in_hospital) / COUNT(*) AS mortality_rate_percent,
  m.median_los AS median_los_days
FROM bin AS b
JOIN med AS m ON b.los_bin = m.los_bin
GROUP BY b.los_bin, b.discharge_location, m.median_los
ORDER BY b.los_bin, b.discharge_location;