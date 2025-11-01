WITH male_inpatients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 47 AND 57
),

aki_admissions AS (
  -- Identify admissions with AKI diagnosis
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    (
      -- ICD-10 N17.x
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^N17'))
      OR
      -- ICD-9 584.x
      (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^584'))
    )
),

icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
),

labs_72h AS (
  -- Labs in first 72h of ICU stay, with reference ranges
  SELECT
    l.subject_id,
    l.hadm_id,
    s.stay_id,
    l.charttime,
    l.itemid,
    l.valuenum,
    l.flag,
    l.ref_range_lower,
    l.ref_range_upper
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN icu_stays s
      ON l.subject_id = s.subject_id
      AND l.hadm_id = s.hadm_id
      AND l.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
  WHERE
    l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
),

lab_instability AS (
  -- For each ICU stay, count abnormal labs and critical events in first 72h
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    COUNTIF(l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper) AS instability_score,
    COUNTIF(l.flag = 'abnormal' OR l.flag = 'critical') AS critical_event_count
  FROM
    icu_stays s
    LEFT JOIN labs_72h l
      ON s.subject_id = l.subject_id
      AND s.hadm_id = l.hadm_id
      AND s.stay_id = l.stay_id
  GROUP BY
    s.subject_id, s.hadm_id, s.stay_id
),

aki_icu_stays AS (
  -- ICU stays for AKI admissions
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.los
  FROM
    icu_stays s
    JOIN aki_admissions a
      ON s.subject_id = a.subject_id
      AND s.hadm_id = a.hadm_id
),

control_icu_stays AS (
  -- ICU stays for male inpatients aged 47–57 without AKI
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.los
  FROM
    icu_stays s
    JOIN male_inpatients m
      ON s.subject_id = m.subject_id
      AND s.hadm_id = m.hadm_id
    LEFT JOIN aki_admissions a
      ON s.subject_id = a.subject_id
      AND s.hadm_id = a.hadm_id
  WHERE
    a.hadm_id IS NULL
),

aki_results AS (
  SELECT
    'AKI' AS cohort,
    COUNT(*) AS n_stays,
    AVG(lab.instability_score) AS mean_lab_instability_score_72h,
    AVG(lab.critical_event_count) AS mean_critical_event_count_72h,
    AVG(a.los) AS avg_icu_los_days,
    AVG(CAST(m.hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality_rate
  FROM
    aki_icu_stays a
    LEFT JOIN lab_instability lab
      ON a.subject_id = lab.subject_id
      AND a.hadm_id = lab.hadm_id
      AND a.stay_id = lab.stay_id
    LEFT JOIN male_inpatients m
      ON a.subject_id = m.subject_id
      AND a.hadm_id = m.hadm_id
),

control_results AS (
  SELECT
    'Control' AS cohort,
    COUNT(*) AS n_stays,
    AVG(lab.instability_score) AS mean_lab_instability_score_72h,
    AVG(lab.critical_event_count) AS mean_critical_event_count_72h,
    AVG(c.los) AS avg_icu_los_days,
    AVG(CAST(m.hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality_rate
  FROM
    control_icu_stays c
    LEFT JOIN lab_instability lab
      ON c.subject_id = lab.subject_id
      AND c.hadm_id = lab.hadm_id
      AND c.stay_id = lab.stay_id
    LEFT JOIN male_inpatients m
      ON c.subject_id = m.subject_id
      AND c.hadm_id = m.hadm_id
)

SELECT * FROM aki_results
UNION ALL
SELECT * FROM control_results
ORDER BY cohort DESC;