WITH target_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4'
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 8 THEN '5-8'
    END AS los_group,
    CASE
      WHEN EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` icu WHERE icu.hadm_id = a.hadm_id) THEN 'ICU'
      ELSE 'No ICU'
    END AS icu_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
      WHERE dx.hadm_id = a.hadm_id
        AND LOWER(d.long_title) LIKE '%deep vein thrombosis%'
    )
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
),

noninvasive_counts AS (
  SELECT
    ta.hadm_id,
    ta.los_group,
    ta.icu_flag,
    COUNT(pr.hadm_id) AS noninvasive_count
  FROM
    target_admissions ta
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON ta.hadm_id = pr.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpr
    ON pr.icd_code = dpr.icd_code AND pr.icd_version = dpr.icd_version
  WHERE
    LOWER(dpr.long_title) NOT LIKE '%invasive%'
    AND LOWER(dpr.long_title) NOT LIKE '%surgical%'
  GROUP BY
    ta.hadm_id, ta.los_group, ta.icu_flag
)

SELECT
  los_group,
  icu_flag,
  COUNT(hadm_id) AS admission_count,
  AVG(noninvasive_count) AS mean_noninvasive_per_admission
FROM
  noninvasive_counts
GROUP BY
  los_group, icu_flag
ORDER BY
  los_group, icu_flag;