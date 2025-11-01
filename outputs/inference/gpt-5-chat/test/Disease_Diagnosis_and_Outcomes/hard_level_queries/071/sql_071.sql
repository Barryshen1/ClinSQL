WITH patients_filtered AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
),
ami_admissions AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE (
      (d.icd_version = 9 AND d.icd_code LIKE '410%')
      OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
    )
),
icu_stays AS (
  SELECT DISTINCT
    subject_id,
    hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
drg_info AS (
  SELECT
    subject_id,
    hadm_id,
    drg_severity
  FROM `physionet-data.mimiciv_3_1_hosp.drgcodes`
),
ami_icu_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    p.anchor_age,
    drg.drg_severity,
    p.gender,
    pat.dod,
    DATE_DIFF(pat.dod, adm.dischtime, DAY) AS days_to_death
  FROM ami_admissions a
  JOIN icu_stays icu
    ON a.subject_id = icu.subject_id AND a.hadm_id = icu.hadm_id
  JOIN patients_filtered p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON a.subject_id = adm.subject_id AND a.hadm_id = adm.hadm_id
  LEFT JOIN drg_info drg
    ON a.subject_id = drg.subject_id AND a.hadm_id = drg.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON a.subject_id = pat.subject_id
),
complications AS (
  SELECT DISTINCT
    subject_id,
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE (
      (d.icd_version = 9 AND (
        d.icd_code LIKE '99591%' OR d.icd_code LIKE '99592%' OR
        d.icd_code LIKE '434%' OR d.icd_code LIKE '584%'
      ))
      OR (d.icd_version = 10 AND (
        d.icd_code LIKE 'A41%' OR d.icd_code LIKE 'I63%' OR d.icd_code LIKE 'N17%'
      ))
    )
),
general_inpatient_cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    drg.drg_severity
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN patients_filtered pf
    ON adm.subject_id = pf.subject_id
  LEFT JOIN drg_info drg
    ON adm.subject_id = drg.subject_id AND adm.hadm_id = drg.hadm_id
  WHERE adm.hadm_id NOT IN (SELECT hadm_id FROM ami_admissions)
),
ami_risk_stats AS (
  SELECT
    APPROX_QUANTILES(drg_severity, 4)[OFFSET(2)] AS median_risk_score,
    APPROX_QUANTILES(drg_severity, 4)[OFFSET(1)] AS iqr25,
    APPROX_QUANTILES(drg_severity, 4)[OFFSET(3)] AS iqr75
  FROM ami_icu_cohort
)
SELECT
  COUNT(DISTINCT ai.hadm_id) AS n_ami_icu,
  (SELECT median_risk_score FROM ami_risk_stats) AS median_risk_score,
  STRUCT((SELECT iqr25 FROM ami_risk_stats),
         (SELECT iqr75 FROM ami_risk_stats)) AS iqr_risk_score,
  SUM(CASE WHEN ai.days_to_death IS NOT NULL AND ai.days_to_death <= 90 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_90d_rate,
  SUM(CASE WHEN c.hadm_id IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) AS major_complication_rate,
  AVG(CASE WHEN (ai.dod IS NULL OR ai.days_to_death > 90) THEN DATE_DIFF(ai.dischtime, ai.admittime, DAY) END) AS survivor_los,
  SAFE_DIVIDE(
    (SELECT COUNT(*) FROM general_inpatient_cohort g
      WHERE g.drg_severity <= (SELECT median_risk_score FROM ami_risk_stats)),
    (SELECT COUNT(*) FROM general_inpatient_cohort)
  ) AS risk_percentile
FROM ami_icu_cohort ai
LEFT JOIN complications c
  ON ai.subject_id = c.subject_id AND ai.hadm_id = c.hadm_id;