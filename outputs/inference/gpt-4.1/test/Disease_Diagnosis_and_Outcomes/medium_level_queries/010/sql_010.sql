WITH cohort AS (
  -- Select male patients age 78-88 with AMI, exclude shock/resp failure
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_ami
      ON a.hadm_id = d_ami.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    -- AMI ICD codes
    AND (
      (d_ami.icd_version = 9 AND REGEXP_CONTAINS(d_ami.icd_code, r'^410'))
      OR (d_ami.icd_version = 10 AND (REGEXP_CONTAINS(d_ami.icd_code, r'^I21') OR REGEXP_CONTAINS(d_ami.icd_code, r'^I22')))
    )
    -- Exclude admissions with shock or respiratory failure
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_excl
      WHERE d_excl.hadm_id = a.hadm_id
        AND (
          -- Cardiogenic shock
          (d_excl.icd_version = 9 AND d_excl.icd_code = '78551')
          OR (d_excl.icd_version = 10 AND d_excl.icd_code = 'R570')
          -- Respiratory failure
          OR (d_excl.icd_version = 9 AND (d_excl.icd_code = '51881' OR d_excl.icd_code = '51884'))
          OR (d_excl.icd_version = 10 AND REGEXP_CONTAINS(d_excl.icd_code, r'^J96'))
        )
    )
),

comorbidities AS (
  -- For each admission, count unique comorbidity categories (excluding AMI, shock, resp failure)
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT CASE
      WHEN (
        -- CKD
        (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^585'))
        OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^N18'))
      ) THEN 'CKD'
      WHEN (
        -- Diabetes
        (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^250'))
        OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^E1[0-4]'))
      ) THEN 'Diabetes'
      WHEN (
        -- Hypertension
        (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^401'))
        OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I10'))
      ) THEN 'HTN'
      WHEN (
        -- CHF
        (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^428'))
        OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I50'))
      ) THEN 'CHF'
      WHEN (
        -- COPD
        (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^496'))
        OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^J44'))
      ) THEN 'COPD'
      WHEN (
        -- Cancer
        (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^140|^141|^142|^143|^144|^145|^146|^147|^148|^149|^150|^151|^152|^153|^154|^155|^156|^157|^158|^159|^160|^161|^162|^163|^164|^165|^170|^171|^172|^174|^175|^176|^179|^180|^181|^182|^183|^184|^185|^186|^187|^188|^189|^190|^191|^192|^193|^194|^195|^196|^197|^198|^199'))
        OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^C'))
      ) THEN 'Cancer'
      WHEN (
        -- Peripheral vascular disease
        (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^4439'))
        OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I73'))
      ) THEN 'PVD'
      WHEN (
        -- Dementia
        (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^290'))
        OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^F03'))
      ) THEN 'Dementia'
      WHEN (
        -- Liver disease
        (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^571'))
        OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^K74'))
      ) THEN 'Liver'
      WHEN (
        -- Stroke
        (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^434'))
        OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I63'))
      ) THEN 'Stroke'
      ELSE NULL
    END) AS n_comorbidities,
    MAX(CASE
      WHEN (
        (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^585'))
        OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^N18'))
      ) THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE
      WHEN (
        (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^250'))
        OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^E1[0-4]'))
      ) THEN 1 ELSE 0 END) AS has_diabetes
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON c.hadm_id = d.hadm_id
  WHERE
    -- Exclude AMI, shock, resp failure codes
    NOT (
      (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^410|^78551|^51881|^51884'))
      OR (d.icd_version = 10 AND (REGEXP_CONTAINS(d.icd_code, r'^I21|^I22|^R570|^J96')))
    )
  GROUP BY c.subject_id, c.hadm_id
),

final_cohort AS (
  -- Merge cohort and comorbidity info
  SELECT
    c.*,
    IFNULL(cm.n_comorbidities, 0) AS n_comorbidities,
    IFNULL(cm.has_ckd, 0) AS has_ckd,
    IFNULL(cm.has_diabetes, 0) AS has_diabetes
  FROM
    cohort c
    LEFT JOIN comorbidities cm
      ON c.subject_id = cm.subject_id AND c.hadm_id = cm.hadm_id
),

quartiles AS (
  -- Assign LOS quartile and comorbidity burden
  SELECT
    *,
    NTILE(4) OVER (ORDER BY los) AS los_quartile,
    CASE
      WHEN n_comorbidities <= 1 THEN 'Low'
      WHEN n_comorbidities <= 3 THEN 'Medium'
      ELSE 'High'
    END AS comorbidity_burden
  FROM final_cohort
),

agg AS (
  -- Aggregate by LOS quartile and comorbidity burden
  SELECT
    los_quartile,
    comorbidity_burden,
    COUNT(*) AS n_admissions,
    SUM(hospital_expire_flag) AS n_deaths,
    AVG(hospital_expire_flag) AS mortality_rate,
    SUM(has_ckd) AS n_ckd,
    SUM(has_diabetes) AS n_diabetes
  FROM quartiles
  GROUP BY los_quartile, comorbidity_burden
),

-- Wilson score interval for 95% CI
results AS (
  SELECT
    los_quartile,
    comorbidity_burden,
    n_admissions,
    mortality_rate,
    -- Wilson score interval calculation
    (
      (mortality_rate + (1.96*1.96)/(2*n_admissions) - 1.96*SQRT((mortality_rate*(1-mortality_rate) + (1.96*1.96)/(4*n_admissions)) / n_admissions))
      / (1 + (1.96*1.96)/n_admissions)
    ) AS mortality_95ci_lower,
    (
      (mortality_rate + (1.96*1.96)/(2*n_admissions) + 1.96*SQRT((mortality_rate*(1-mortality_rate) + (1.96*1.96)/(4*n_admissions)) / n_admissions))
      / (1 + (1.96*1.96)/n_admissions)
    ) AS mortality_95ci_upper,
    SAFE_DIVIDE(n_ckd, n_admissions) AS ckd_prevalence,
    SAFE_DIVIDE(n_diabetes, n_admissions) AS diabetes_prevalence
  FROM agg
)

SELECT
  los_quartile,
  comorbidity_burden,
  n_admissions,
  ROUND(mortality_rate, 4) AS mortality_rate,
  ROUND(mortality_95ci_lower, 4) AS mortality_95ci_lower,
  ROUND(mortality_95ci_upper, 4) AS mortality_95ci_upper,
  ROUND(ckd_prevalence, 4) AS ckd_prevalence,
  ROUND(diabetes_prevalence, 4) AS diabetes_prevalence
FROM results
ORDER BY los_quartile, comorbidity_burden;