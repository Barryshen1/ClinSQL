WITH ards_cohort AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, pat.anchor_age, pat.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.subject_id = diag.subject_id
   AND adm.hadm_id = diag.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 71 AND 81
    AND (
         (diag.icd_version = 9 AND diag.icd_code = '51882')
         OR (diag.icd_version = 10 AND diag.icd_code = 'J80')
    )
),
instability AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    SUM(
      CASE
        WHEN vit.label = 'Heart Rate' AND (ce.valuenum < 50 OR ce.valuenum > 110) THEN 1
        WHEN vit.label = 'Mean blood pressure' AND ce.valuenum < 65 THEN 1
        WHEN vit.label = 'GCS Total' AND ce.valuenum < 13 THEN 1
        ELSE 0
      END
    ) AS instability_score
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN ards_cohort ards
    ON icu.subject_id = ards.subject_id
   AND icu.hadm_id = ards.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.subject_id = ce.subject_id
   AND icu.hadm_id = ce.hadm_id
   AND icu.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` vit
    ON ce.itemid = vit.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 72 HOUR)
    AND vit.label IN ('Heart Rate', 'Mean blood pressure', 'GCS Total')
  GROUP BY icu.subject_id, icu.hadm_id
),
p90 AS (
  SELECT APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS p90_score
  FROM instability
),
high_risk AS (
  SELECT i.subject_id, i.hadm_id, i.instability_score
  FROM instability i
  CROSS JOIN p90
  WHERE i.instability_score >= p90.p90_score
),
critical_labs AS (
  SELECT le.subject_id, le.hadm_id,
         COUNTIF(
           (dl.label = 'Lactate' AND le.valuenum > 4)
           OR (dl.label = 'Creatinine' AND le.valuenum > 3)
           OR (dl.label = 'Bilirubin, Total' AND le.valuenum > 12)
         ) AS critical_count,
         COUNT(*) AS total_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  GROUP BY le.subject_id, le.hadm_id
),
-- Outcomes for high risk ARDS group
high_risk_outcomes AS (
  SELECT
    hr.subject_id,
    hr.hadm_id,
    adm.hospital_expire_flag,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    cl.critical_count, cl.total_count
  FROM high_risk hr
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON hr.subject_id = adm.subject_id
   AND hr.hadm_id = adm.hadm_id
  LEFT JOIN critical_labs cl
    ON hr.subject_id = cl.subject_id
   AND hr.hadm_id = cl.hadm_id
),
general_outcomes AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.hospital_expire_flag,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    cl.critical_count, cl.total_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  LEFT JOIN critical_labs cl
    ON adm.subject_id = cl.subject_id
   AND adm.hadm_id = cl.hadm_id
)
SELECT
  'High risk ARDS male 71-81' AS group_name,
  COUNT(*) AS n,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(los_days) AS mean_los_days,
  SUM(critical_count)/SUM(total_count) AS critical_lab_rate
FROM high_risk_outcomes
UNION ALL
SELECT
  'General inpatients' AS group_name,
  COUNT(*) AS n,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(los_days) AS mean_los_days,
  SUM(critical_count)/SUM(total_count) AS critical_lab_rate
FROM general_outcomes;