WITH stroke_adms AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS adm_los
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      ON a.hadm_id = dx.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dxd
      ON dx.icd_code = dxd.icd_code
     AND dx.icd_version = dxd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
    AND LOWER(dxd.long_title) LIKE '%ischemic stroke%'
  GROUP BY
    p.subject_id,
    a.hadm_id,
    adm_los
),
icu_flag AS (
  SELECT
    hadm_id,
    'ICU' AS icu_status
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY
    hadm_id
),
imaging_counts AS (
  SELECT
    sa.hadm_id,
    COUNT(pi.icd_code) AS img_count
  FROM
    stroke_adms sa
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
      ON sa.hadm_id = pi.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
      ON pi.icd_code = dip.icd_code
     AND pi.icd_version = dip.icd_version
  WHERE
    LOWER(dip.long_title) LIKE '%ct%'
    OR LOWER(dip.long_title) LIKE '%mri%'
    OR LOWER(dip.long_title) LIKE '%xray%'
    OR LOWER(dip.long_title) LIKE '%ultrasound%'
  GROUP BY
    sa.hadm_id
)
SELECT
  CASE
    WHEN sa.adm_los BETWEEN 1 AND 4 THEN '1–4 days'
    ELSE '5–7 days'
  END AS los_group,
  COALESCE(icu.icu_status, 'No ICU') AS icu_status,
  ROUND(AVG(IFNULL(ic.img_count, 0)), 2) AS mean_imaging_procs,
  MIN(IFNULL(ic.img_count, 0)) AS min_imaging_procs,
  MAX(IFNULL(ic.img_count, 0)) AS max_imaging_procs
FROM
  stroke_adms sa
  LEFT JOIN imaging_counts ic
    ON sa.hadm_id = ic.hadm_id
  LEFT JOIN icu_flag icu
    ON sa.hadm_id = icu.hadm_id
GROUP BY
  los_group,
  icu_status
ORDER BY
  los_group,
  icu_status;