WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4'
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7'
    END AS los_category,
    CASE
      WHEN i.stay_id IS NOT NULL THEN 'Yes'
      ELSE 'No'
    END AS icu_use
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  LEFT JOIN
    physionet-data.mimiciv_3_1_icu.icustays i
    ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE LOWER(dd.long_title) LIKE '%transient%cerebral%ischemic%attack%'
    )
),

imaging_counts AS (
  SELECT
    c.hadm_id,
    c.los_category,
    c.icu_use,
    COUNT(pr.icd_code) AS imaging_count
  FROM
    cohort c
  LEFT JOIN
    physionet-data.mimiciv_3_1_hosp.procedures_icd pr
    ON c.hadm_id = pr.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dp
    ON pr.icd_code = dp.icd_code AND pr.icd_version = dp.icd_version
  WHERE
    LOWER(dp.long_title) LIKE '%ct%head%'
    OR LOWER(dp.long_title) LIKE '%mri%'
    OR LOWER(dp.long_title) LIKE '%angiography%'
  GROUP BY
    c.hadm_id, c.los_category, c.icu_use
)

SELECT
  los_category,
  icu_use,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(3)] AS p75
FROM
  imaging_counts
WHERE
  los_category IS NOT NULL
GROUP BY
  los_category, icu_use
ORDER BY
  los_category, icu_use;