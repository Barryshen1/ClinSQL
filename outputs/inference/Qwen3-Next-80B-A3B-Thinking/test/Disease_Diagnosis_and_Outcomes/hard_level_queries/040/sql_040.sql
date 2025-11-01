WITH ich_admissions AS (
  SELECT 
    a.hadm_id, 
    a.subject_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag, 
    p.anchor_age, 
    p.gender, 
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('430', '431', '432'))
      OR (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
    )
),

gcs_data AS (
  SELECT 
    c.hadm_id, 
    c.value AS gcs_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN ich_admissions i 
    ON c.hadm_id = i.hadm_id
  WHERE 
    c.itemid = 223900
    AND c.charttime >= i.admittime
  QUALIFY ROW_NUMBER() OVER (PARTITION BY c.hadm_id ORDER BY c.charttime) = 1
),

hematoma_volume AS (
  SELECT 
    c.hadm_id, 
    c.valuenum AS volume
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN ich_admissions i 
    ON c.hadm_id = i.hadm_id
  WHERE 
    c.itemid = 220767
    AND c.charttime >= i.admittime
  QUALIFY ROW_NUMBER() OVER (PARTITION BY c.hadm_id ORDER BY c.charttime) = 1
),

intraventricular AS (
  SELECT 
    d.hadm_id, 
    1 AS intraventricular_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN ich_admissions i 
    ON d.hadm_id = i.hadm_id
  WHERE 
    (d.icd_version = 10 AND (d.icd_code LIKE 'I61.0%' OR d.icd_code LIKE 'I61.1%'))
    OR (d.icd_version = 9 AND d.icd_code = '431.0')
  GROUP BY d.hadm_id
),

infratentorial AS (
  SELECT 
    d.hadm_id, 
    1 AS infratentorial_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN ich_admissions i 
    ON d.hadm_id = i.hadm_id
  WHERE 
    (d.icd_version = 10 AND (d.icd_code LIKE 'I61.5%' OR d.icd_code LIKE 'I61.6%'))
  GROUP BY d.hadm_id
),

ich_scores AS (
  SELECT 
    i.hadm_id,
    i.admittime,
    i.dischtime,
    i.hospital_expire_flag,
    i.dod,
    COALESCE(g.gcs_value, NULL) AS gcs_value,
    COALESCE(h.volume, NULL) AS volume,
    COALESCE(iv.intraventricular_flag, 0) AS intraventricular,
    COALESCE(inf.infratentorial_flag, 0) AS infratentorial,
    CASE
      WHEN g.gcs_value >= 13 THEN 0
      WHEN g.gcs_value >= 9 THEN 1
      WHEN g.gcs_value >= 6 THEN 2
      WHEN g.gcs_value >= 4 THEN 3
      WHEN g.gcs_value = 3 THEN 4
      ELSE NULL
    END AS gcs_score,
    CASE WHEN h.volume >= 30 THEN 1 ELSE 0 END AS volume_score,
    0 AS age_score,
    iv.intraventricular_flag AS intraventricular_score,
    inf.infratentorial_flag AS location_score
  FROM ich_admissions i
  LEFT JOIN gcs_data g ON i.hadm_id = g.hadm_id
  LEFT JOIN hematoma_volume h ON i.hadm_id = h.hadm_id
  LEFT JOIN intraventricular iv ON i.hadm_id = iv.hadm_id
  LEFT JOIN infratentorial inf ON i.hadm_id = inf.hadm_id
),

ich_scores_with_total AS (
  SELECT 
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    dod,
    gcs_score,
    volume_score,
    age_score,
    intraventricular_score,
    location_score,
    (gcs_score + volume_score + age_score + intraventricular_score + location_score) AS ich_score
  FROM ich_scores
),

quintiles AS (
  SELECT 
    hadm_id,
    ich_score,
    NTILE(5) OVER (ORDER BY ich_score) AS quintile
  FROM ich_scores_with_total
)

SELECT 
  q.quintile,
  COUNT(*) AS n,
  ROUND(100.0 * SUM(CASE WHEN dod IS NOT NULL AND DATE_DIFF(dod, i.admittime, DAY) <= 30 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_30day_pct,
  ROUND(100.0 * SUM(CASE WHEN EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    WHERE d.hadm_id = i.hadm_id 
      AND (d.icd_code = 'G91.9' OR d.icd_code = 'J18.9')
  ) THEN 1 ELSE 0 END) / COUNT(*), 2) AS major_complication_pct,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY DATE_DIFF(i.dischtime, i.admittime, DAY)) AS median_survivor_los
FROM quintiles q
JOIN ich_admissions i ON q.hadm_id = i.hadm_id
WHERE i.hospital_expire_flag = 0
GROUP BY q.quintile
ORDER BY q.quintile;