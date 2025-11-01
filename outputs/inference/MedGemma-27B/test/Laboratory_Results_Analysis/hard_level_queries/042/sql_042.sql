WITH
  -- Identify patients with ICH based on ICD-10 codes
  ich_patients AS (
    SELECT DISTINCT
      a.subject_id,
      a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.hadm_id = d.hadm_id
    WHERE
      d.icd_code LIKE 'I60%' -- ICH codes start with I60
      AND a.gender = 'M'
      AND a.anchor_age BETWEEN 73 AND 83
  ),
  -- Define abnormal lab values based on reference ranges
  abnormal_labs AS (
    SELECT
      l.subject_id,
      l.hadm_id,
      l.charttime,
      l.itemid,
      l.value,
      l.valuenum,
      l.valueuom,
      l.ref_range_lower,
      l.ref_range_upper,
      l.flag
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    JOIN ich_patients AS ip
      ON l.subject_id = ip.subject_id AND l.hadm_id = ip.hadm_id
    WHERE
      l.charttime BETWEEN ip.admittime AND ip.admittime + INTERVAL '48' HOUR
      AND (
        (
          l.valuenum < l.ref_range_lower
          OR l.valuenum > l.ref_range_upper
        )
        OR l.flag = 'ABNORMAL'
      )
  ),
  -- Calculate the number of distinct abnormal lab types per patient
  instability_score AS (
    SELECT
      subject_id,
      hadm_id,
      COUNT(DISTINCT itemid) AS abnormal_lab_types
    FROM abnormal_labs
    GROUP BY
      subject_id,
      hadm_id
  ),
  -- Calculate LOS and mortality for ICH patients
  ich_outcomes AS (
    SELECT
      a.subject_id,
      a.hadm_id,
      a.los,
      a.hospital_expire_flag,
      is.abnormal_lab_types
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN instability_score AS is
      ON a.subject_id = is.subject_id AND a.hadm_id = is.hadm_id
    WHERE
      a.admittime BETWEEN '2150-01-01' AND '2150-12-31' -- Filter for a specific time range
  ),
  -- Calculate LOS and mortality for all inpatients
  all_outcomes AS (
    SELECT
      a.subject_id,
      a.hadm_id,
      a.los,
      a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    WHERE
      a.admittime BETWEEN '2150-01-01' AND '2150-12-31' -- Filter for the same time range
  )
SELECT
  -- Calculate quartiles for instability score
  NTILE(4) OVER (ORDER BY is.abnormal_lab_types) AS instability_quartile,
  COUNT(DISTINCT is.subject_id) AS patient_count,
  AVG(a.los) AS mean_los,
  AVG(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate
FROM ich_outcomes AS a
JOIN instability_score AS is
  ON a.subject_id = is.subject_id AND a.hadm_id = is.hadm_id
GROUP BY
  instability_quartile
ORDER BY
  instability_quartile;