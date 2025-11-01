WITH cohort_labs AS (
  SELECT
    ie.stay_id,
    ie.subject_id,
    ie.hadm_id,
    ie.intime,
    ie.outtime,
    COUNT(le.labevent_id) AS lab_count
  FROM
    physionet-data.mimiciv_3_1_icu.icustays ie
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON ie.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions adm
    ON ie.hadm_id = adm.hadm_id
  LEFT JOIN
    physionet-data.mimiciv_3_1_hosp.labevents le
    ON le.hadm_id = ie.hadm_id
    AND le.charttime >= ie.intime
    AND le.charttime <= DATETIME_ADD(ie.intime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 70 AND 80
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd dx
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
        ON dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
      WHERE dx.hadm_id = ie.hadm_id
        AND (
          (dx.icd_version = 9 AND dx.icd_code LIKE '428%')
          OR
          (dx.icd_version = 10 AND dx.icd_code LIKE 'I50%')
        )
    )
  GROUP BY
    ie.stay_id, ie.subject_id, ie.hadm_id, ie.intime, ie.outtime
),

general_labs AS (
  SELECT
    ie.stay_id,
    ie.subject_id,
    ie.hadm_id,
    ie.intime,
    ie.outtime,
    COUNT(le.labevent_id) AS lab_count
  FROM
    physionet-data.mimiciv_3_1_icu.icustays ie
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON ie.subject_id = p.subject_id
  LEFT JOIN
    physionet-data.mimiciv_3_1_hosp.labevents le
    ON le.hadm_id = ie.hadm_id
    AND le.charttime >= ie.intime
    AND le.charttime <= DATETIME_ADD(ie.intime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 70 AND 80
  GROUP BY
    ie.stay_id, ie.subject_id, ie.hadm_id, ie.intime, ie.outtime
),

hf_stats AS (
  SELECT
    'Heart Failure Cohort' AS group_name,
    AVG(lab_count) AS mean_labs,
    APPROX_QUANTILES(lab_count, 100)[OFFSET(50)] AS median_labs,
    APPROX_QUANTILES(lab_count, 100)[OFFSET(75)] AS percentile_75_labs,
    APPROX_QUANTILES(lab_count, 100)[OFFSET(95)] AS percentile_95_labs,
    AVG(DATETIME_DIFF(outtime, intime, HOUR)) AS mean_icu_los_hours,
    AVG(CAST(adm.hospital_expire_flag AS FLOAT64)) AS hospital_mortality
  FROM
    cohort_labs cl
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions adm
    ON cl.hadm_id = adm.hadm_id
),

general_stats AS (
  SELECT
    'General ICU Population' AS group_name,
    AVG(lab_count) AS mean_labs,
    APPROX_QUANTILES(lab_count, 100)[OFFSET(50)] AS median_labs,
    APPROX_QUANTILES(lab_count, 100)[OFFSET(75)] AS percentile_75_labs,
    APPROX_QUANTILES(lab_count, 100)[OFFSET(95)] AS percentile_95_labs,
    AVG(DATETIME_DIFF(outtime, intime, HOUR)) AS mean_icu_los_hours,
    AVG(CAST(adm.hospital_expire_flag AS FLOAT64)) AS hospital_mortality
  FROM
    general_labs gl
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions adm
    ON gl.hadm_id = adm.hadm_id
)

SELECT * FROM hf_stats
UNION ALL
SELECT * FROM general_stats
ORDER BY group_name;