WITH admissions_cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    CASE
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      ELSE NULL
    END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON diag.subject_id = a.subject_id AND diag.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS did
    ON diag.icd_code = did.icd_code AND diag.icd_version = did.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND (
          LOWER(did.long_title) LIKE '%transient ischemic attack%'
          OR LOWER(did.long_title) LIKE '%tia%'
        )
),

imaging_per_adm AS (
  SELECT
    ac.hadm_id,
    ac.subject_id,
    ac.admittime,
    ac.dischtime,
    ac.los_group,
    -- Count distinct CT/MRI charttimes for CT/MRI studies
    COUNT(DISTINCT CASE
                    WHEN LOWER(dit.label) LIKE '%ct%' OR LOWER(dit.label) LIKE '%mri%'
                    THEN ce.charttime
                  END) AS imaging_count
  FROM admissions_cohort AS ac
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.hadm_id = ac.hadm_id
   AND ce.charttime >= ac.admittime
   AND ce.charttime <= ac.dischtime
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS dit
    ON dit.itemid = ce.itemid
  GROUP BY ac.hadm_id, ac.subject_id, ac.admittime, ac.dischtime, ac.los_group
),

final_rows AS (
  SELECT
    ip.hadm_id,
    ip.subject_id,
    ip.admittime,
    ip.dischtime,
    ip.los_group,
    ip.imaging_count,
    (SELECT COUNT(*) > 0
     FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
     WHERE ic.hadm_id = ip.hadm_id AND ic.subject_id = ip.subject_id) AS icu_present
  FROM imaging_per_adm AS ip
)

SELECT
  CASE WHEN icu_present THEN 'Yes' ELSE 'No' END AS icu_use,
  los_group,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(2)] AS median_imaging_count,
  (APPROX_QUANTILES(imaging_count, 4)[OFFSET(3)] - APPROX_QUANTILES(imaging_count, 4)[OFFSET(1)]) AS iqr_imaging_count
FROM final_rows
GROUP BY icu_present, los_group
ORDER BY icu_present, los_group;