WITH pneumonia_admissions AS (
  -- Identify admissions with pneumonia as primary diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    d.seq_num = 1
    AND LOWER(dd.long_title) LIKE '%pneumonia%'
),

eligible_patients AS (
  -- Filter patients by gender and age
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    pa.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    pneumonia_admissions pa
    ON p.subject_id = pa.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
),

comorbidity_scores AS (
  -- Compute comorbidity score (Elixhauser-like) excluding pneumonia
  SELECT
    ep.subject_id,
    ep.hadm_id,
    COUNT(DISTINCT d.icd_code) AS comorbidity_count
  FROM
    eligible_patients ep
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON ep.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    d.seq_num > 1
    AND LOWER(dd.long_title) NOT LIKE '%pneumonia%'
  GROUP BY
    ep.subject_id, ep.hadm_id
),

patients_with_quartiles AS (
  -- Assign comorbidity quartile
  SELECT
    ep.*,
    cs.comorbidity_count,
    NTILE(4) OVER (ORDER BY cs.comorbidity_count) AS comorbidity_quartile
  FROM
    eligible_patients ep
  JOIN
    comorbidity_scores cs
    ON ep.hadm_id = cs.hadm_id
),

top_comorbidity_cohort AS (
  -- Top quartile only
  SELECT *
  FROM patients_with_quartiles
  WHERE comorbidity_quartile = 4
),

complications AS (
  -- Identify major complications (e.g., respiratory failure, septic shock)
  SELECT DISTINCT
    d.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    d.seq_num > 1
    AND (
      LOWER(dd.long_title) LIKE '%respiratory failure%'
      OR LOWER(dd.long_title) LIKE '%septic shock%'
      OR LOWER(dd.long_title) LIKE '%acute kidney failure%'
    )
),

survival_days AS (
  SELECT
    hadm_id,
    DATE_DIFF(dischtime, admittime, DAY) AS survival_days
  FROM top_comorbidity_cohort
  WHERE dischtime IS NOT NULL AND admittime IS NOT NULL
),

final_stats AS (
  SELECT
    -- Mortality %
    AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_percent,

    -- Complication %
    AVG(CASE WHEN c.hadm_id IS NOT NULL THEN 1 ELSE 0 END) * 100 AS complication_percent,

    -- Median survival days
    APPROX_QUANTILES(s.survival_days, 2)[OFFSET(1)] AS median_survival_days
  FROM
    top_comorbidity_cohort t
  LEFT JOIN
    complications c
    ON t.hadm_id = c.hadm_id
  LEFT JOIN
    survival_days s
    ON t.hadm_id = s.hadm_id
)

SELECT * FROM final_stats;