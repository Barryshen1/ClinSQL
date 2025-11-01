WITH upper_gi_bleed_adm AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      USING (subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      USING (icd_code, icd_version)
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING (subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    -- ICD-9 codes 578.0, 578.1, 578.9
    -- ICD-10 codes K92.0, K92.1, K92.2
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('5780','5781','5789'))
      OR (d.icd_version = 10 AND d.icd_code IN ('K92.0','K92.1','K92.2'))
    )
),
first_icustay AS (
  SELECT
    ug.subject_id,
    ug.hadm_id,
    ug.admittime,
    ug.dischtime,
    ug.hospital_expire_flag,
    icu.stay_id,
    icu.intime
  FROM
    upper_gi_bleed_adm ug
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON ug.subject_id = icu.subject_id
      AND ug.hadm_id    = icu.hadm_id
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY ug.subject_id, ug.hadm_id ORDER BY icu.intime) = 1
),
diag_counts AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.admittime,
    f.dischtime,
    f.hospital_expire_flag,
    COUNT(ce.charttime) AS proc_count
  FROM
    first_icustay f
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON ce.subject_id = f.subject_id
      AND ce.hadm_id    = f.hadm_id
      AND ce.stay_id    = f.stay_id
      AND ce.charttime BETWEEN f.intime AND TIMESTAMP_ADD(f.intime, INTERVAL 72 HOUR)
  GROUP BY
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.admittime,
    f.dischtime,
    f.hospital_expire_flag
),
with_quartiles AS (
  SELECT
    dc.*,
    NTILE(4) OVER (ORDER BY dc.proc_count) AS quartile
  FROM
    diag_counts dc
)
SELECT
  quartile,
  ROUND(AVG(proc_count), 2)         AS mean_procedure_count,
  ROUND(AVG(
    TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0
  ), 2)                               AS mean_hospital_los_days,
  ROUND(AVG(hospital_expire_flag), 3) AS in_hospital_mortality_rate
FROM
  with_quartiles
GROUP BY
  quartile
ORDER BY
  quartile;