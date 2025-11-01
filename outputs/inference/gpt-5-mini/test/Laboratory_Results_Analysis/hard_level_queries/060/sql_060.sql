WITH patients_f52_62 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 52 AND 62
),

-- Admissions for those patients
adm AS (
  SELECT a.*
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patients_f52_62 p USING(subject_id)
),

-- Identify admissions with a cardiac arrest diagnosis by matching diagnosis description text
cardiac_adm_ids AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%cardiac arrest%'
),

-- Base admissions annotated with icustay (if any) and window start/end (first 48h)
base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    icu.stay_id,
    icu.intime AS icu_intime,
    COALESCE(icu.intime, a.admittime) AS window_start,
    TIMESTAMP_ADD(COALESCE(icu.intime, a.admittime), INTERVAL 48 HOUR) AS window_end
  FROM adm a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON a.subject_id = icu.subject_id AND a.hadm_id = icu.hadm_id
),

-- Instability flags per admission (cardiac cohort only)
instability_flags AS (
  SELECT
    b.subject_id,
    b.hadm_id,
    b.stay_id,
    b.window_start,
    b.window_end,

    (CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
      JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
      WHERE ce.subject_id = b.subject_id
        AND ( (b.stay_id IS NOT NULL AND ce.stay_id = b.stay_id) OR (b.stay_id IS NULL AND ce.hadm_id = b.hadm_id) )
        AND ce.charttime BETWEEN b.window_start AND b.window_end
        AND ce.valuenum IS NOT NULL
        AND (
            (LOWER(di.label) LIKE '%systolic%' AND ce.valuenum < 90)
         OR (LOWER(di.label) LIKE '%mean arterial pressure%' AND ce.valuenum < 65)
         OR (LOWER(di.label) LIKE '%map%' AND ce.valuenum < 65)
        )
    ) THEN 1 ELSE 0 END) AS hypotension_flag,

    (CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
      JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
      WHERE ce.subject_id = b.subject_id
        AND ( (b.stay_id IS NOT NULL AND ce.stay_id = b.stay_id) OR (b.stay_id IS NULL AND ce.hadm_id = b.hadm_id) )
        AND ce.charttime BETWEEN b.window_start AND b.window_end
        AND ce.valuenum IS NOT NULL
        AND LOWER(di.label) LIKE '%heart rate%'
        AND ce.valuenum > 120
    ) THEN 1 ELSE 0 END) AS tachycardia_flag,

    (CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
      JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
      WHERE ce.subject_id = b.subject_id
        AND ( (b.stay_id IS NOT NULL AND ce.stay_id = b.stay_id) OR (b.stay_id IS NULL AND ce.hadm_id = b.hadm_id) )
        AND ce.charttime BETWEEN b.window_start AND b.window_end
        AND ce.valuenum IS NOT NULL
        AND (LOWER(di.label) LIKE '%oxygen saturation%' OR LOWER(di.label) LIKE '%spo2%' OR LOWER(di.label) LIKE '%sao2%')
        AND ce.valuenum < 90
    ) THEN 1 ELSE 0 END) AS hypoxemia_flag,

    (CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
      JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON le.itemid = li.itemid
      WHERE le.hadm_id = b.hadm_id
        AND le.charttime BETWEEN b.window_start AND b.window_end
        AND le.valuenum IS NOT NULL
        AND LOWER(li.label) LIKE '%lactate%'
        AND le.valuenum > 2
    ) THEN 1 ELSE 0 END) AS lactate_flag,

    (CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
      JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ie.itemid = di.itemid
      WHERE ie.subject_id = b.subject_id
        AND ( (b.stay_id IS NOT NULL AND ie.stay_id = b.stay_id) OR (b.stay_id IS NULL AND ie.hadm_id = b.hadm_id) )
        AND ie.starttime <= b.window_end AND COALESCE(ie.endtime, ie.starttime) >= b.window_start
        AND (
          LOWER(di.label) LIKE '%norepinephrine%' OR LOWER(di.label) LIKE '%epinephrine%'
          OR LOWER(di.label) LIKE '%vasopressin%' OR LOWER(di.label) LIKE '%phenylephrine%'
          OR LOWER(di.label) LIKE '%dopamine%'
        )
        AND (ie.amount IS NOT NULL AND ie.amount > 0)
    ) THEN 1 ELSE 0 END) AS vasopressor_flag

  FROM base b
  WHERE b.hadm_id IN (SELECT hadm_id FROM cardiac_adm_ids)
),

-- Instability scores aggregated per cardiac admission
instability_scores AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    window_start,
    window_end,
    (hypotension_flag + tachycardia_flag + hypoxemia_flag + lactate_flag + vasopressor_flag) AS instability_score,
    hypotension_flag,
    tachycardia_flag,
    hypoxemia_flag,
    lactate_flag,
    vasopressor_flag
  FROM instability_flags
),

-- Critical lab event detection per admission within first 48h after admittime
critical_labs_per_adm AS (
  SELECT
    a.hadm_id,
    MAX(CASE WHEN (le.flag IS NOT NULL AND LOWER(le.flag) <> '') THEN 1
             WHEN (le.valuenum IS NOT NULL AND (
                    (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
                 OR (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
               )) THEN 1
             ELSE 0 END) AS any_critical_lab_within_48h
  FROM adm a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = a.hadm_id
    AND le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY a.hadm_id
),

-- Group-level summaries: cardiac cohort vs general inpatients
grouped AS (
  -- Cardiac cohort
  SELECT
    'post_cardiac_arrest' AS group_label,
    COUNT(DISTINCT b.hadm_id) AS n_admissions,
    SAFE_DIVIDE(SUM(IF(cl.any_critical_lab_within_48h = 1, 1, 0)), COUNT(DISTINCT b.hadm_id)) AS prop_any_critical_lab,
    -- median hospital LOS in days via scalar subquery over the cohort
    (
      SELECT q[OFFSET(2)]
      FROM (
        SELECT APPROX_QUANTILES(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0, 4) AS q
        FROM base b2
        WHERE b2.hadm_id IN (SELECT hadm_id FROM cardiac_adm_ids)
      )
    ) AS median_hosp_los_days,
    SAFE_DIVIDE(SUM(IF(b.hospital_expire_flag = 1, 1, 0)), COUNT(DISTINCT b.hadm_id)) AS hospital_mortality,
    -- instability Q1 and median for cardiac cohort via scalar subquery over instability_scores
    (
      SELECT q[OFFSET(1)]
      FROM (
        SELECT APPROX_QUANTILES(instability_score, 4) AS q
        FROM instability_scores
      )
    ) AS instability_q1,
    (
      SELECT q[OFFSET(2)]
      FROM (
        SELECT APPROX_QUANTILES(instability_score, 4) AS q
        FROM instability_scores
      )
    ) AS instability_median
  FROM base b
  LEFT JOIN critical_labs_per_adm cl ON b.hadm_id = cl.hadm_id
  LEFT JOIN instability_scores inst ON b.hadm_id = inst.hadm_id
  WHERE b.hadm_id IN (SELECT hadm_id FROM cardiac_adm_ids)

  UNION ALL

  -- General inpatient cohort: same age/gender but excluding admissions with cardiac arrest diagnosis
  SELECT
    'general_inpatients' AS group_label,
    COUNT(DISTINCT b.hadm_id) AS n_admissions,
    SAFE_DIVIDE(SUM(IF(cl.any_critical_lab_within_48h = 1, 1, 0)), COUNT(DISTINCT b.hadm_id)) AS prop_any_critical_lab,
    (
      SELECT q[OFFSET(2)]
      FROM (
        SELECT APPROX_QUANTILES(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0, 4) AS q
        FROM base b2
        WHERE b2.hadm_id NOT IN (SELECT hadm_id FROM cardiac_adm_ids)
      )
    ) AS median_hosp_los_days,
    SAFE_DIVIDE(SUM(IF(b.hospital_expire_flag = 1, 1, 0)), COUNT(DISTINCT b.hadm_id)) AS hospital_mortality,
    NULL AS instability_q1,
    NULL AS instability_median
  FROM base b
  LEFT JOIN critical_labs_per_adm cl ON b.hadm_id = cl.hadm_id
  WHERE b.hadm_id NOT IN (SELECT hadm_id FROM cardiac_adm_ids)
)

SELECT *
FROM grouped
ORDER BY group_label;