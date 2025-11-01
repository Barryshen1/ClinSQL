WITH hf_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON p.subject_id = di.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
    AND LOWER(dd.long_title) LIKE '%heart failure%'
),
adm_with_los AS (
  SELECT a.subject_id,
         a.hadm_id,
         DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN hf_patients hfp
    ON a.subject_id = hfp.subject_id
  WHERE a.dischtime IS NOT NULL
),
icu_flagged AS (
  SELECT awl.subject_id,
         awl.hadm_id,
         awl.los_days,
         CASE WHEN COUNT(ic.stay_id) > 0 THEN 1 ELSE 0 END AS icu_flag
  FROM adm_with_los awl
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic
    ON awl.subject_id = ic.subject_id
    AND awl.hadm_id = ic.hadm_id
  GROUP BY awl.subject_id, awl.hadm_id, awl.los_days
),
radiology_counts AS (
  SELECT icuf.subject_id,
         icuf.hadm_id,
         icuf.los_days,
         icuf.icu_flag,
         COUNT(proc.icd_code) AS rad_ct_count
  FROM icu_flagged icuf
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON icuf.subject_id = proc.subject_id
    AND icuf.hadm_id = proc.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON proc.icd_code = dp.icd_code
    AND proc.icd_version = dp.icd_version
  WHERE dp.long_title IS NULL
        OR LOWER(dp.long_title) LIKE '%radiography%'
        OR LOWER(dp.long_title) LIKE '%computed tomography%'
        OR LOWER(dp.long_title) LIKE '%x-ray%'
        OR LOWER(dp.long_title) LIKE '%ct %'
  GROUP BY icuf.subject_id, icuf.hadm_id, icuf.los_days, icuf.icu_flag
),
classified AS (
  SELECT *,
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
    END AS stay_group
  FROM radiology_counts
  WHERE los_days BETWEEN 1 AND 8
)
SELECT
  stay_group,
  icu_flag,
  q[OFFSET(CAST(ROUND(0.25*(ARRAY_LENGTH(q)-1)) AS INT64))] AS p25_rad_ct,
  q[OFFSET(CAST(ROUND(0.50*(ARRAY_LENGTH(q)-1)) AS INT64))] AS p50_rad_ct,
  q[OFFSET(CAST(ROUND(0.75*(ARRAY_LENGTH(q)-1)) AS INT64))] AS p75_rad_ct
FROM (
  SELECT
    stay_group,
    icu_flag,
    APPROX_QUANTILES(rad_ct_count, 100) AS q
  FROM classified
  GROUP BY stay_group, icu_flag
)
ORDER BY stay_group, icu_flag;