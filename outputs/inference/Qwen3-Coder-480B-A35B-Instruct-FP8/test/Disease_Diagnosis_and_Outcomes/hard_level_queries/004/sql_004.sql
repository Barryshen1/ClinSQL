WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.hospital_expire_flag,
    p.anchor_age,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Composite risk score components
    p.anchor_age AS age,
    CASE WHEN a.admission_type = 'EMERGENCY' THEN 1 ELSE 0 END AS is_emergency,
    -- Count of secondary diagnoses as comorbidity proxy
    (SELECT COUNT(*) FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di WHERE di.hadm_id = a.hadm_id AND di.seq_num > 1) AS comorbidity_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.seq_num = 1
        AND (
          (d.icd_version = 9 AND d.icd_code IN ('431', '432'))
          OR
          (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I61|^I62'))
        )
    )
),

risk_scored AS (
  SELECT
    *,
    age + (is_emergency * 5) + comorbidity_count AS risk_score,
    NTILE(4) OVER (ORDER BY age + (is_emergency * 5) + comorbidity_count) AS risk_quartile
  FROM cohort
),

complications AS (
  SELECT
    di.hadm_id,
    MAX(CASE
      WHEN d.icd_version = 9 AND d.icd_code IN ('410', '411', '412', '427') THEN 1
      WHEN d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I21|^I22|^I23|^I46|^I47') THEN 1
      ELSE 0
    END) AS cardiac_complication,
    MAX(CASE
      WHEN d.icd_version = 9 AND d.icd_code IN ('430', '433', '434', '435', '436', '437', '438') THEN 1
      WHEN d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I60|^I63|^I65|^I66|^I67|^I68|^G45|^G46') THEN 1
      ELSE 0
    END) AS neuro_complication
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    di.seq_num > 1
  GROUP BY
    di.hadm_id
),

final_data AS (
  SELECT
    rs.*,
    COALESCE(c.cardiac_complication, 0) AS cardiac_complication,
    COALESCE(c.neuro_complication, 0) AS neuro_complication
  FROM
    risk_scored rs
  LEFT JOIN
    complications c
  ON
    rs.hadm_id = c.hadm_id
)

SELECT
  risk_quartile,
  COUNT(*) AS patient_count,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(cardiac_complication) AS cardiac_complication_rate,
  AVG(neuro_complication) AS neuro_complication_rate,
  APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los_days ELSE NULL END, 2)[OFFSET(1)] AS median_los_survivors
FROM
  final_data
GROUP BY
  risk_quartile
ORDER BY
  risk_quartile;