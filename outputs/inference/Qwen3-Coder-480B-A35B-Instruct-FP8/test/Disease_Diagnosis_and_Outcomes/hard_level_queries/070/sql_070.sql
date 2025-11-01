WITH dvt_patients AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND (
      dd.icd_code LIKE '453.4%' OR dd.icd_code LIKE 'I82.4%' OR dd.icd_code LIKE 'I82.8%'
    )
    AND d.seq_num <= 5
),

elixhauser AS (
  SELECT
    dp.hadm_id,
    COUNT(*) AS elixhauser_score
  FROM
    dvt_patients dp
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  ON
    dp.hadm_id = dx.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddx
  ON
    dx.icd_code = ddx.icd_code
    AND dx.icd_version = ddx.icd_version
  WHERE
    ddx.icd_code IN (
      '39891', '40201', '40211', '40291', '40401', '40403', '40411', '40413', '40491', '40493',
      '4280', '4281', '42820', '42821', '42822', '42823', '42830', '42831', '42832', '42833',
      '42840', '42841', '42842', '42843', '4289', '428', '429', '4290', '4291', '4292', '4293',
      '4294', '4295', '4296', '4297', '4298', '4299',
      '45342', '45341', '45340', '4538', '4539', '45981', '45989', '4599', 'I82409', 'I82419',
      'I828', 'I829', 'I82A19', 'I82B19', 'I82C19'
    )
  GROUP BY
    dp.hadm_id
),

patients_with_comorbidity AS (
  SELECT
    dp.*,
    COALESCE(e.elixhauser_score, 0) AS elixhauser_score
  FROM
    dvt_patients dp
  LEFT JOIN
    elixhauser e
  ON
    dp.hadm_id = e.hadm_id
),

comorbidity_75th_percentile AS (
  SELECT
    APPROX_QUANTILES(elixhauser_score, 100)[OFFSET(75)] AS score_75th
  FROM
    patients_with_comorbidity
),

high_comorbidity_cohort AS (
  SELECT
    pwc.*
  FROM
    patients_with_comorbidity pwc
  CROSS JOIN
    comorbidity_75th_percentile cp
  WHERE
    pwc.elixhauser_score >= cp.score_75th
),

outcomes AS (
  SELECT
    hadm_id,
    CASE
      WHEN hospital_expire_flag = 1 THEN 1
      WHEN dod IS NOT NULL AND DATE_DIFF(dod, dischtime, DAY) <= 30 THEN 1
      ELSE 0
    END AS mortality_30d,
    CASE
      WHEN hospital_expire_flag = 1 THEN DATE_DIFF(dischtime, admittime, DAY)
      WHEN dod IS NOT NULL THEN DATE_DIFF(dod, admittime, DAY)
      ELSE NULL
    END AS survival_days
  FROM
    high_comorbidity_cohort
),

complication_flag AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN seq_num > 1 THEN 1 ELSE 0 END) AS major_complication
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    seq_num > 1
  GROUP BY
    hadm_id
),

final_cohort AS (
  SELECT
    hcc.*,
    o.mortality_30d,
    o.survival_days,
    COALESCE(cf.major_complication, 0) AS major_complication
  FROM
    high_comorbidity_cohort hcc
  LEFT JOIN
    outcomes o
  ON
    hcc.hadm_id = o.hadm_id
  LEFT JOIN
    complication_flag cf
  ON
    hcc.hadm_id = cf.hadm_id
),

risk_score_quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY elixhauser_score + anchor_age) AS risk_score_quartile
  FROM
    final_cohort
)

SELECT
  COUNT(*) AS cohort_size,
  AVG(mortality_30d) AS mortality_30d_rate,
  AVG(major_complication) AS major_complication_rate,
  APPROX_QUANTILES(survival_days, 2)[OFFSET(1)] AS median_survival_days,
  APPROX_QUANTILES(risk_score_quartile, 4) AS risk_score_quartiles
FROM
  risk_score_quartiles;