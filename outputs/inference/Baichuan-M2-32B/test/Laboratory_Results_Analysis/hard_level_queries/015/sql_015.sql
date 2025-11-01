WITH
  -- Define ischemic stroke ICD-10 codes (I63.*)
  stroke_codes AS (
    SELECT 'I63' AS icd_prefix
  ),
  -- Cohort: male patients aged 49-59 at admission with ischemic stroke
  cohort AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      -- Compute age at admission: approximate using anchor_year
      EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE
      p.gender = 'M'
      AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 49 AND 59
      AND d.icd_version = 10
      AND d.icd_code LIKE 'I63%'  -- ischemic stroke
    GROUP BY p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, p.anchor_year
  ),
  -- Get lab events for the cohort in the first 72 hours
  labs AS (
    SELECT
      c.subject_id,
      c.hadm_id,
      le.labevent_id,
      le.valuenum,
      le.valueuom,
      le.charttime,
      -- Check if abnormal: only if reference range exists
      CASE
        WHEN dl.ref_range_lower IS NOT NULL AND dl.ref_range_upper IS NOT NULL
          THEN CASE
               WHEN le.valuenum < dl.ref_range_lower OR le.valuenum > dl.ref_range_upper
                 THEN 1
               ELSE 0
               END
        ELSE NULL
      END AS is_abnormal
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON c.hadm_id = le.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
      ON le.itemid = dl.itemid
    WHERE
      le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  ),
  -- Instability score: count of abnormal labs per patient
  instability_score AS (
    SELECT
      subject_id,
      hadm_id,
      COUNT(CASE WHEN is_abnormal = 1 THEN 1 END) AS instability_count
    FROM labs
    GROUP BY subject_id, hadm_id
  ),
  -- Compute 75th percentile of instability_count
  percentile AS (
    SELECT
      APPROX_QUANTILES(instability_count, 100)[OFFSET(75)] AS p75
    FROM instability_score
  ),
  -- High-instability group: instability_count >= p75
  high_instability AS (
    SELECT
      i.subject_id,
      i.hadm_id,
      i.instability_count,
      c.admittime,
      c.dischtime,
      c.hospital_expire_flag,
      c.age_at_admission
    FROM instability_score i
    INNER JOIN cohort c
      ON i.subject_id = c.subject_id AND i.hadm_id = c.hadm_id
    CROSS JOIN percentile p
    WHERE i.instability_count >= p.p75
  ),
  -- Control group: male, age 49-59 at admission, without ischemic stroke
  controls AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'M'
      AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 49 AND 59
      -- Exclude stroke patients
      AND NOT EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
          ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
        WHERE d.hadm_id = a.hadm_id
          AND d.icd_version = 10
          AND d.icd_code LIKE 'I63%'
      )
  ),
  -- For high_instability group: compute critical lab rate (proportion with at least one abnormal lab in 72h)
  high_instability_lab_rate AS (
    SELECT
      COUNT(DISTINCT subject_id) AS total_high_instability,
      COUNT(DISTINCT CASE WHEN instability_count > 0 THEN subject_id END) AS with_abnormal_labs
    FROM high_instability
  ),
  -- For control group: compute critical lab rate (proportion with at least one abnormal lab in first 72h)
  control_lab_rate AS (
    SELECT
      COUNT(DISTINCT c.subject_id) AS total_controls,
      COUNT(DISTINCT CASE WHEN l.labevent_id IS NOT NULL THEN c.subject_id END) AS with_abnormal_labs
    FROM controls c
    LEFT JOIN (
      SELECT
        le.subject_id,
        le.hadm_id,
        le.labevent_id,
        -- Check abnormal
        CASE
          WHEN dl.ref_range_lower IS NOT NULL AND dl.ref_range_upper IS NOT NULL
            THEN CASE
                 WHEN le.valuenum < dl.ref_range_lower OR le.valuenum > dl.ref_range_upper
                   THEN 1
                 ELSE 0
                 END
          ELSE NULL
        END AS is_abnormal
      FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
        ON le.itemid = dl.itemid
    ) l ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id
    WHERE
      l.is_abnormal = 1
      AND le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  ),
  -- For high_instability group: compute LOS and mortality
  high_instability_stats AS (
    SELECT
      AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS avg_los,
      AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
    FROM high_instability
  )
-- Now, we want to output:
--   p75 (from percentile)
--   avg_los and mortality_rate from high_instability_stats
--   critical lab rate for high_instability: with_abnormal_labs / total_high_instability
--   critical lab rate for controls: with_abnormal_labs / total_controls

SELECT
  p.p75 AS instability_75th_percentile,
  h.avg_los,
  h.mortality_rate,
  (hi.with_abnormal_labs * 1.0 / hi.total_high_instability) AS high_instability_critical_lab_rate,
  (c.with_abnormal_labs * 1.0 / c.total_controls) AS control_critical_lab_rate
FROM percentile p
CROSS JOIN high_instability_stats h
CROSS JOIN high_instability_lab_rate hi
CROSS JOIN control_lab_rate c;