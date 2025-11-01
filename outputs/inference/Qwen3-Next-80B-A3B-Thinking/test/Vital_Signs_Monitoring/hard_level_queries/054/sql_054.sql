WITH specific_cohort AS (
  SELECT 
    i.stay_id, 
    i.hadm_id, 
    i.intime, 
    i.los, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = i.hadm_id
        AND dd.long_title LIKE '%acute respiratory failure%'
    )
),

specific_composite AS (
  SELECT 
    sc.stay_id,
    sc.los,
    sc.hospital_expire_flag,
    SUM(CASE WHEN c.itemid = 52 AND c.valuenum < 65 THEN 1 ELSE 0 END) +
    SUM(CASE WHEN c.itemid = 220045 AND c.valuenum > 100 THEN 1 ELSE 0 END) AS composite_score
  FROM specific_cohort sc
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON sc.stay_id = c.stay_id
    AND c.charttime BETWEEN sc.intime AND sc.intime + INTERVAL '72' HOUR
  GROUP BY sc.stay_id, sc.los, sc.hospital_expire_flag
),

general_composite AS (
  SELECT 
    i.stay_id,
    i.los,
    a.hospital_expire_flag,
    SUM(CASE WHEN c.itemid = 52 AND c.valuenum < 65 THEN 1 ELSE 0 END) +
    SUM(CASE WHEN c.itemid = 220045 AND c.valuenum > 100 THEN 1 ELSE 0 END) AS composite_score
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON i.stay_id = c.stay_id
    AND c.charttime BETWEEN i.intime AND i.intime + INTERVAL '72' HOUR
  GROUP BY i.stay_id, i.los, a.hospital_expire_flag
)

(
  SELECT 
    'Specific Cohort' AS group_name,
    PERCENTILE_CONT(composite_score, 0.25) AS p25,
    PERCENTILE_CONT(composite_score, 0.5) AS median,
    PERCENTILE_CONT(composite_score, 0.75) AS p75,
    (PERCENTILE_CONT(composite_score, 0.75) - PERCENTILE_CONT(composite_score, 0.25)) AS iqr,
    AVG(composite_score) AS avg_burden,
    AVG(los) AS avg_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM specific_composite
)

UNION ALL

SELECT 
  'General ICU' AS group_name,
  NULL AS p25,
  NULL AS median,
  NULL AS p75,
  NULL AS iqr,
  AVG(composite_score) AS avg_burden,
  AVG(los) AS avg_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM general_composite;