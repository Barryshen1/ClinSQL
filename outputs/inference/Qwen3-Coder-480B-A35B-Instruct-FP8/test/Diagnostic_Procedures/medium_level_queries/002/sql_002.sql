WITH tia_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN i.hadm_id IS NOT NULL THEN 1
      ELSE 0
    END AS icu_user
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  LEFT JOIN
    physionet-data.mimiciv_3_1_icu.icustays i
    ON a.hadm_id = i.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%transient ischemic attack%'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

procedures_per_admission AS (
  SELECT
    t.hadm_id,
    t.icu_user,
    CASE
      WHEN t.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN t.los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_bin,
    COUNT(pr.hadm_id) AS proc_count
  FROM
    tia_admissions t
  LEFT JOIN
    physionet-data.mimiciv_3_1_hosp.procedures_icd pr
    ON t.hadm_id = pr.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dp
    ON pr.icd_code = dp.icd_code AND pr.icd_version = dp.icd_version
  WHERE
    LOWER(dp.long_title) LIKE '%echocardiogram%'
    OR LOWER(dp.long_title) LIKE '%ultrasound%'
  GROUP BY
    t.hadm_id, t.icu_user, los_bin
)

SELECT
  los_bin,
  icu_user,
  AVG(proc_count) AS mean_procedures_per_admission
FROM
  procedures_per_admission
GROUP BY
  los_bin,
  icu_user
ORDER BY
  los_bin,
  icu_user;