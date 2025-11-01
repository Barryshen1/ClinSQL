WITH stroke_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
    p.anchor_age,
    p.gender,
    CASE WHEN i.hadm_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_status
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN
    (SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays`) i
    ON a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('434', '43401', '43411', '43491', '435', '4350', '4351', '4352', '4353', '4358', '4359'))
      OR
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I63'))
    )
),

comorbidity_count AS (
  SELECT
    hadm_id,
    COUNT(*) AS comorbidity_score
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    seq_num > 1
  GROUP BY
    hadm_id
),

admissions_with_comorbidities AS (
  SELECT
    s.*,
    COALESCE(c.comorbidity_score, 0) AS comorbidity_score,
    CASE
      WHEN s.los <= 5 THEN 'LOS ≤5'
      ELSE 'LOS >5'
    END AS los_group
  FROM
    stroke_admissions s
  LEFT JOIN
    comorbidity_count c
    ON s.hadm_id = c.hadm_id
),

comorbidity_stratified AS (
  SELECT
    *,
    CASE
      WHEN comorbidity_score = 0 THEN 'Low'
      WHEN comorbidity_score BETWEEN 1 AND 2 THEN 'Medium'
      ELSE 'High'
    END AS comorbidity_group
  FROM
    admissions_with_comorbidities
),

mortality_stats AS (
  SELECT
    icu_status,
    los_group,
    comorbidity_group,
    COUNT(*) AS n,
    SUM(hospital_expire_flag) AS deaths,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM
    comorbidity_stratified
  GROUP BY
    icu_status, los_group, comorbidity_group
)

SELECT
  icu_status,
  los_group,
  comorbidity_group,
  n,
  deaths,
  ROUND(mortality_rate * 100, 2) AS mortality_percent,
  ROUND(
    (mortality_rate - 1.96 * SQRT(mortality_rate * (1 - mortality_rate) / n)) * 100,
    2
  ) AS ci_95_lower,
  ROUND(
    (mortality_rate + 1.96 * SQRT(mortality_rate * (1 - mortality_rate) / n)) * 100,
    2
  ) AS ci_95_upper
FROM
  mortality_stats
ORDER BY
  icu_status, los_group, comorbidity_group;