WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admit,
    adm.admittime,
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 51 AND 61
    AND adm.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE LOWER(dd.long_title) LIKE '%diabetes%'
    )
    AND adm.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE LOWER(dd.long_title) LIKE '%acute%'
        AND LOWER(dd.long_title) LIKE '%heart failure%'
    )
),
drug_flags AS (
  SELECT
    c.hadm_id,
    CASE
      WHEN UPPER(pres.drug) LIKE '%INSULIN%' THEN 'insulin'
      WHEN UPPER(pres.drug) LIKE '%METFORMIN%' THEN 'oral'
      WHEN UPPER(pres.drug) LIKE '%GLIPIZIDE%' THEN 'oral'
      WHEN UPPER(pres.drug) LIKE '%GLYBURIDE%' THEN 'oral'
      WHEN UPPER(pres.drug) LIKE '%PIOGLITAZONE%' THEN 'oral'
      WHEN UPPER(pres.drug) LIKE '%SITAGLIPTIN%' THEN 'oral'
      WHEN UPPER(pres.drug) LIKE '%LINAGLIPTIN%' THEN 'oral'
      WHEN UPPER(pres.drug) LIKE '%REPAGLINIDE%' THEN 'oral'
      ELSE NULL
    END AS drug_category,
    -- Flags for time windows
    MAX( CASE
      WHEN pres.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
           AND pres.stoptime > c.admittime THEN 1 ELSE 0 END ) AS first48h_flag,
    MAX( CASE
      WHEN pres.starttime < c.dischtime
           AND pres.stoptime > TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END ) AS last24h_flag
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON c.hadm_id = pres.hadm_id
  WHERE pres.starttime IS NOT NULL
    AND pres.stoptime IS NOT NULL
  GROUP BY c.hadm_id, drug_category
),
summary AS (
  SELECT
    drug_category,
    COUNT(DISTINCT hadm_id) AS n_with_category,
    SUM(first48h_flag) AS had_first48h,
    SUM(last24h_flag) AS had_last24h,
    SUM(CASE WHEN first48h_flag=1 AND last24h_flag=1 THEN 1 ELSE 0 END) AS continued,
    SUM(CASE WHEN first48h_flag=0 AND last24h_flag=1 THEN 1 ELSE 0 END) AS initiated,
    SUM(CASE WHEN first48h_flag=1 AND last24h_flag=0 THEN 1 ELSE 0 END) AS discontinued
  FROM drug_flags
  WHERE drug_category IS NOT NULL
  GROUP BY drug_category
)
SELECT
  s.drug_category,
  s.n_with_category,
  s.had_first48h,
  ROUND(100 * s.had_first48h / c.hadm_count, 1) AS pct_first48h,
  s.had_last24h,
  ROUND(100 * s.had_last24h / c.hadm_count, 1) AS pct_last24h,
  s.continued,
  s.initiated,
  s.discontinued
FROM summary s
CROSS JOIN (SELECT COUNT(DISTINCT hadm_id) AS hadm_count FROM cohort) c
ORDER BY drug_category;