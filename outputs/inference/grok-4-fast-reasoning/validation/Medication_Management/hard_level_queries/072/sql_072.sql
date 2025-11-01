WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND a.dischtime IS NOT NULL
    AND d.icd_version = 10
    AND (d.icd_code LIKE 'E10.1%' OR d.icd_code LIKE 'E11.1%' OR d.icd_code LIKE 'E13.1%')
),
meds_first48 AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.drug,
    pr.gsn,
    pr.starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN cohort c
    ON pr.subject_id = c.subject_id AND pr.hadm_id = c.hadm_id
  WHERE pr.starttime >= c.admittime
    AND pr.starttime < c.admittime + INTERVAL 48 HOUR
),
complexity AS (
  SELECT
    c.*,
    COUNT(DISTINCT COALESCE(CAST(m.gsn AS STRING), m.drug)) AS medication_complexity
  FROM cohort c
  LEFT JOIN meds_first48 m
    ON c.subject_id = m.subject_id AND c.hadm_id = m.hadm_id
  GROUP BY
    c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag
),
interaction_flags AS (
  SELECT
    c.*,
    CASE
      WHEN raas.exists_raas IS NOT NULL THEN 1 ELSE 0
    END AS has_raas,
    CASE
      WHEN k.exists_k IS NOT NULL THEN 1 ELSE 0
    END AS has_k,
    CASE
      WHEN raas.exists_raas IS NOT NULL AND k.exists_k IS NOT NULL THEN 1 ELSE 0
    END AS has_interaction
  FROM complexity c
  LEFT JOIN (
    SELECT
      subject_id,
      hadm_id,
      1 AS exists_raas
    FROM meds_first48
    WHERE drug LIKE '%Lisinopril%'
       OR drug LIKE '%Enalapril%'
       OR drug LIKE '%Ramipril%'
       OR drug LIKE '%Losartan%'
    GROUP BY subject_id, hadm_id
  ) raas
    ON c.subject_id = raas.subject_id AND c.hadm_id = raas.hadm_id
  LEFT JOIN (
    SELECT
      subject_id,
      hadm_id,
      1 AS exists_k
    FROM meds_first48
    WHERE drug LIKE '%Potassium%'
       OR drug LIKE '%KCl%'
       OR drug LIKE '%Spironolactone%'
    GROUP BY subject_id, hadm_id
  ) k
    ON c.subject_id = k.subject_id AND c.hadm_id = k.hadm_id
),
with_pr AS (
  SELECT
    *,
    TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0 AS los_days,
    PERCENT_RANK() OVER (ORDER BY medication_complexity) AS complexity_percentile
  FROM interaction_flags
),
group_summary AS (
  SELECT
    has_interaction,
    AVG(medication_complexity) AS mean_complexity,
    AVG(complexity_percentile) * 100 AS mean_percentile,
    AVG(los_days) AS mean_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM with_pr
  GROUP BY has_interaction
),
top_quartile AS (
  SELECT
    AVG(los_days) AS mean_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM with_pr
  WHERE complexity_percentile >= 0.75
)
SELECT
  CASE has_interaction
    WHEN 1 THEN 'With hyperkalemia-risk drug interactions'
    WHEN 0 THEN 'Without hyperkalemia-risk drug interactions'
  END AS group_name,
  ROUND(mean_complexity, 2) AS mean_complexity,
  ROUND(mean_percentile, 2) AS mean_percentile,
  ROUND(mean_los, 2) AS mean_los_days,
  ROUND(mortality_rate * 100, 2) AS mortality_rate_percent
FROM group_summary
UNION ALL
SELECT
  'Top complexity quartile' AS group_name,
  NULL AS mean_complexity,
  NULL AS mean_percentile,
  ROUND(mean_los, 2) AS mean_los_days,
  ROUND(mortality_rate * 100, 2) AS mortality_rate_percent
FROM top_quartile
ORDER BY
  CASE group_name
    WHEN 'With hyperkalemia-risk drug interactions' THEN 1
    WHEN 'Without hyperkalemia-risk drug interactions' THEN 2
    ELSE 3
  END;