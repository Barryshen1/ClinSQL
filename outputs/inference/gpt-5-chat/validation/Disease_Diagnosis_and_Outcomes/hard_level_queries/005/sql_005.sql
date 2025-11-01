WITH all_females_43_53 AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod,
    icu.stay_id,
    di.long_title AS diagnosis_label,
    ce.valuenum AS risk_score
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON a.hadm_id = icu.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code
    AND d.icd_version = di.icd_version
  LEFT JOIN (
    SELECT subject_id, hadm_id, stay_id, MAX(valuenum) AS valuenum
    FROM `physionet-data.mimiciv_3_1_icu.chartevents`
    WHERE itemid IN (
      SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items`
      WHERE LOWER(label) LIKE '%oasis%'
    )
    GROUP BY subject_id, hadm_id, stay_id
  ) ce
    ON icu.subject_id = ce.subject_id
    AND icu.hadm_id = ce.hadm_id
    AND icu.stay_id = ce.stay_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
),
hf_icu_cohort AS (
  SELECT DISTINCT *
  FROM all_females_43_53
  WHERE (diagnosis_label LIKE '%heart failure%'
         OR diagnosis_label LIKE 'Heart failure%')
),
cohort_metrics AS (
  SELECT
    COUNT(DISTINCT hf.subject_id) AS n_patients,
    APPROX_QUANTILES(hf.risk_score, 100)[OFFSET(50)] AS median_risk_score,
    APPROX_QUANTILES(hf.risk_score, 100)[OFFSET(25)] AS risk_q1,
    APPROX_QUANTILES(hf.risk_score, 100)[OFFSET(75)] AS risk_q3,
    AVG(CASE WHEN hf.dod IS NOT NULL 
              AND DATETIME_DIFF(hf.dod, hf.admittime, DAY) <= 30 THEN 1 ELSE 0 END) AS mortality_30d_rate,
    AVG(CASE WHEN hf.diagnosis_label LIKE '%sepsis%'
             OR hf.diagnosis_label LIKE '%stroke%'
             OR hf.diagnosis_label LIKE '%acute myocardial%' THEN 1 ELSE 0 END) AS major_complication_rate,
    AVG(CASE WHEN a.hospital_expire_flag = 0 THEN DATETIME_DIFF(hf.dischtime, hf.admittime, DAY) END) AS avg_los_survivors
  FROM hf_icu_cohort hf
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON hf.subject_id = a.subject_id
    AND hf.hadm_id = a.hadm_id
),
risk_percentile AS (
  SELECT
    hf.subject_id,
    hf.risk_score,
    PERCENT_RANK() OVER (ORDER BY af.risk_score) AS risk_percentile_vs_all
  FROM hf_icu_cohort hf
  JOIN all_females_43_53 af
    ON af.subject_id = hf.subject_id
)
SELECT
  cm.*,
  AVG(rp.risk_percentile_vs_all) AS avg_percentile_in_all_females_43_53
FROM cohort_metrics cm
CROSS JOIN risk_percentile rp;