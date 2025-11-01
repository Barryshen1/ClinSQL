WITH
-- Step 1: Define the base cohort of female patients aged 52-62
admissions_base AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
),

-- Step 2: Identify stroke admissions and classify them
stroke_diagnoses AS (
  SELECT
    hadm_id,
    CASE
      -- Hemorrhagic Stroke
      WHEN
        (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('430', '431', '432'))
        OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I60', 'I61', 'I62'))
        THEN 'Hemorrhagic'
      -- Ischemic Stroke
      WHEN
        (icd_version = 9 AND (SUBSTR(icd_code, 1, 4) IN ('433.01', '433.11', '433.21', '433.31', '433.81', '433.91') OR SUBSTR(icd_code, 1, 3) = '434'))
        OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'I63')
        THEN 'Ischemic'
      ELSE NULL
    END AS stroke_type,
    -- Prioritize Hemorrhagic over Ischemic if both are coded
    CASE
      WHEN
        (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('430', '431', '432'))
        OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I60', 'I61', 'I62'))
        THEN 1
      WHEN
        (icd_version = 9 AND (SUBSTR(icd_code, 1, 4) IN ('433.01', '433.11', '433.21', '433.31', '433.81', '433.91') OR SUBSTR(icd_code, 1, 3) = '434'))
        OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'I63')
        THEN 2
      ELSE 99
    END AS priority
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
),

stroke_cohort AS (
  SELECT
    hadm_id,
    stroke_type
  FROM (
    SELECT
      hadm_id,
      stroke_type,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY priority) AS rn
    FROM
      stroke_diagnoses
    WHERE
      stroke_type IS NOT NULL AND hadm_id IN (SELECT hadm_id FROM admissions_base)
  ) AS ranked_strokes
  WHERE
    rn = 1
),

-- Step 3: Calculate comorbidities based on Charlson Comorbidity Index
comorbidities AS (
  SELECT
    hadm_id,
    -- Diabetes flag for final output
    MAX(
      CASE
        WHEN
          (icd_version = 9 AND STARTS_WITH(icd_code, '250'))
          OR (icd_version = 10 AND STARTS_WITH(icd_code, 'E08'))
          OR (icd_version = 10 AND STARTS_WITH(icd_code, 'E09'))
          OR (icd_version = 10 AND STARTS_WITH(icd_code, 'E10'))
          OR (icd_version = 10 AND STARTS_WITH(icd_code, 'E11'))
          OR (icd_version = 10 AND STARTS_WITH(icd_code, 'E13'))
          THEN 1
        ELSE 0
      END
    ) AS has_diabetes,
    -- CKD flag for final output
    MAX(
      CASE
        WHEN
          (icd_version = 9 AND STARTS_WITH(icd_code, '585'))
          OR (icd_version = 10 AND STARTS_WITH(icd_code, 'N18'))
          THEN 1
        ELSE 0
      END
    ) AS has_ckd,
    
    -- Charlson conditions flags for score calculation
    MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '410' OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I21', 'I22')) THEN 1 ELSE 0 END) AS mi,
    MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '428' OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'I50') THEN 1 ELSE 0 END) AS chf,
    MAX(CASE WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) IN ('440', '441') OR SUBSTR(icd_code, 1, 4) IN ('443.2', '443.8', '443.9', '447.1', '557.1', '557.9')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I70', 'I71', 'I73')) THEN 1 ELSE 0 END) AS pvd,
    MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '430' AND '438' OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) BETWEEN 'I60' AND 'I69') THEN 1 ELSE 0 END) AS cvd,
    MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '290' OR (icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('G30', 'F01', 'F02') OR SUBSTR(icd_code, 1, 4) = 'F05.1')) THEN 1 ELSE 0 END) AS dementia,
    MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '490' AND '508' OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) BETWEEN 'J40' AND 'J47') THEN 1 ELSE 0 END) AS cpd,
    MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '714' OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('M05', 'M06')) THEN 1 ELSE 0 END) AS rheum,
    MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('531','532','533','534') THEN 1 ELSE 0 END) AS pud,
    MAX(CASE WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) = '571' OR SUBSTR(icd_code, 1, 4) = '573.3') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('K70', 'K73', 'K74')) THEN 1 ELSE 0 END) AS mld,
    MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 4) IN ('250.0', '250.1', '250.2', '250.3')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 4) IN ('E10.0', 'E10.1', 'E10.9', 'E11.0', 'E11.1', 'E11.9', 'E13.0', 'E13.1', 'E13.9', 'E14.0', 'E14.1', 'E14.9')) THEN 1 ELSE 0 END) AS diab,
    MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 4) IN ('250.4', '250.5', '250.6', '250.7', '250.8', '250.9')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 4) IN ('E10.2', 'E10.3', 'E10.4', 'E10.5', 'E10.7', 'E11.2', 'E11.3', 'E11.4', 'E11.5', 'E11.7')) THEN 1 ELSE 0 END) AS diab_comp,
    MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '342' OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'G81') THEN 1 ELSE 0 END) AS paraplegia,
    MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '585' OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'N18') THEN 1 ELSE 0 END) AS renal,
    MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '140' AND '172' OR (icd_version = 10 AND (SUBSTR(icd_code, 1, 3) BETWEEN 'C00' AND 'C75' OR SUBSTR(icd_code, 1, 3) = 'C80')) THEN 1 ELSE 0 END) AS cancer,
    MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 4) IN ('572.2', '572.3', '572.4') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('K71', 'K72')) THEN 1 ELSE 0 END) AS sld,
    MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('196', '197', '198') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) BETWEEN 'C77' AND 'C79') THEN 1 ELSE 0 END) AS mets,
    MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '042' OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('B20', 'B21', 'B22')) THEN 1 ELSE 0 END) AS hiv
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE hadm_id IN (SELECT hadm_id FROM stroke_cohort)
  GROUP BY
    hadm_id
),

-- Step 4: Calculate Charlson score and create final cohort table
final_cohort AS (
  SELECT
    ab.hadm_id,
    sc.stroke_type,
    ab.hospital_expire_flag,
    ab.hospital_los,
    COALESCE(com.has_diabetes, 0) AS has_diabetes,
    COALESCE(com.has_ckd, 0) AS has_ckd,
    (
        COALESCE(com.mi, 0) * 1 + COALESCE(com.chf, 0) * 1 + COALESCE(com.pvd, 0) * 1 +
        COALESCE(com.cvd, 0) * 1 + COALESCE(com.dementia, 0) * 1 + COALESCE(com.cpd, 0) * 1 +
        COALESCE(com.rheum, 0) * 1 + COALESCE(com.pud, 0) * 1 + COALESCE(com.mld, 0) * 1 +
        COALESCE(com.diab, 0) * 1 + COALESCE(com.diab_comp, 0) * 2 + COALESCE(com.paraplegia, 0) * 2 +
        COALESCE(com.renal, 0) * 2 + COALESCE(com.cancer, 0) * 2 + COALESCE(com.sld, 0) * 3 +
        COALESCE(com.mets, 0) * 6 + COALESCE(com.hiv, 0) * 6
    ) AS charlson_score
  FROM
    admissions_base AS ab
  INNER JOIN
    stroke_cohort AS sc ON ab.hadm_id = sc.hadm_id
  LEFT JOIN
    comorbidities AS com ON ab.hadm_id = com.hadm_id
  WHERE
    ab.hospital_los >= 0
),

-- Step 5: Assign comorbidity tertiles
cohort_with_tertiles AS (
    SELECT
        *,
        NTILE(3) OVER (ORDER BY charlson_score) AS comorbidity_tertile
    FROM
        final_cohort
)

-- Step 6: Final aggregation and reporting
SELECT
  stroke_type,
  comorbidity_tertile,
  COUNT(hadm_id) AS number_of_admissions,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_pct,
  APPROX_QUANTILES(hospital_los, 100)[OFFSET(50)] AS median_hospital_los_days,
  ROUND(AVG(has_diabetes) * 100, 2) AS diabetes_prevalence_pct,
  ROUND(AVG(has_ckd) * 100, 2) AS ckd_prevalence_pct
FROM
  cohort_with_tertiles
GROUP BY
  stroke_type,
  comorbidity_tertile
ORDER BY
  stroke_type,
  comorbidity_tertile;