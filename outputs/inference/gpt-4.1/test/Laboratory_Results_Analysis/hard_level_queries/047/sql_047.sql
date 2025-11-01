WITH ards_patients AS (
  -- Identify male inpatients aged 71-81 with ARDS diagnosis
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag,
    i.intime,
    i.outtime,
    i.los
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
    JOIN physionet-data.mimiciv_3_1_hosp.admissions a
      ON p.subject_id = a.subject_id
    JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      ON a.hadm_id = d.hadm_id
    JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    JOIN physionet-data.mimiciv_3_1_icu.icustays i
      ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
    AND (
      -- ARDS ICD-10: J80, ICD-9: 518.82, 518.5
      (d.icd_version = 10 AND d.icd_code = 'J80')
      OR (d.icd_version = 9 AND d.icd_code IN ('51882', '5185'))
      OR LOWER(dd.long_title) LIKE '%acute respiratory distress%'
    )
),

instability_scores AS (
  -- Count critical labs in first 72h of ICU stay
  SELECT
    ap.subject_id,
    ap.hadm_id,
    ap.stay_id,
    COUNT(DISTINCT le.labevent_id) AS instability_score
  FROM
    ards_patients ap
    JOIN physionet-data.mimiciv_3_1_hosp.labevents le
      ON ap.subject_id = le.subject_id
      AND ap.hadm_id = le.hadm_id
      AND le.charttime BETWEEN ap.intime AND TIMESTAMP_ADD(ap.intime, INTERVAL 72 HOUR)
  WHERE
    le.flag = 'abnormal'
  GROUP BY
    ap.subject_id, ap.hadm_id, ap.stay_id
),

percentile_90 AS (
  -- Calculate 90th percentile instability score
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS p90_score
  FROM
    instability_scores
),

high_instability_patients AS (
  -- Patients at/above 90th percentile
  SELECT
    ap.subject_id,
    ap.hadm_id,
    ap.stay_id,
    ap.anchor_age,
    ap.gender,
    ap.hospital_expire_flag,
    ap.los,
    ap.intime,
    ap.outtime,
    s.instability_score
  FROM
    ards_patients ap
    JOIN instability_scores s
      ON ap.subject_id = s.subject_id
      AND ap.hadm_id = s.hadm_id
      AND ap.stay_id = s.stay_id
    CROSS JOIN percentile_90 p
  WHERE
    s.instability_score >= p.p90_score
),

high_instability_lab_rates AS (
  -- Critical lab rate for high instability patients (first 72h)
  SELECT
    hip.subject_id,
    hip.hadm_id,
    hip.stay_id,
    COUNT(DISTINCT le.labevent_id) AS critical_lab_count
  FROM
    high_instability_patients hip
    JOIN physionet-data.mimiciv_3_1_hosp.labevents le
      ON hip.subject_id = le.subject_id
      AND hip.hadm_id = le.hadm_id
      AND le.charttime BETWEEN hip.intime AND TIMESTAMP_ADD(hip.intime, INTERVAL 72 HOUR)
  WHERE
    le.flag = 'abnormal'
  GROUP BY
    hip.subject_id, hip.hadm_id, hip.stay_id
),

general_inpatient_lab_rates AS (
  -- Critical lab rate for all inpatients (first 72h of admission)
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNT(DISTINCT le.labevent_id) AS critical_lab_count
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
    JOIN physionet-data.mimiciv_3_1_hosp.labevents le
      ON a.subject_id = le.subject_id
      AND a.hadm_id = le.hadm_id
      AND le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  WHERE
    le.flag = 'abnormal'
  GROUP BY
    a.subject_id, a.hadm_id
)

-- Final output: summary for high instability ARDS patients and comparison to general inpatients
SELECT
  'ARDS high instability (>=90th percentile)' AS cohort,
  COUNT(DISTINCT hip.subject_id) AS n_patients,
  SUM(CASE WHEN hip.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
  AVG(hip.los) AS mean_icu_los,
  AVG(lr.critical_lab_count) AS mean_critical_lab_count_72h
FROM
  high_instability_patients hip
  JOIN high_instability_lab_rates lr
    ON hip.subject_id = lr.subject_id
    AND hip.hadm_id = lr.hadm_id
    AND hip.stay_id = lr.stay_id

UNION ALL

SELECT
  'General inpatients' AS cohort,
  COUNT(DISTINCT a.subject_id) AS n_patients,
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
  NULL AS mean_icu_los,
  AVG(lr.critical_lab_count) AS mean_critical_lab_count_72h
FROM
  physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN general_inpatient_lab_rates lr
    ON a.subject_id = lr.subject_id
    AND a.hadm_id = lr.hadm_id;