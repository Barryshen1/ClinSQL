WITH chestpain_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON a.subject_id = di.subject_id
      AND a.hadm_id    = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dxd
      ON di.icd_code    = dxd.icd_code
      AND di.icd_version = dxd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND LOWER(dxd.long_title) LIKE '%chest pain%'
  GROUP BY
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag
),
first_troponin AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    MIN(le.charttime)                         AS first_trop_time
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
      ON le.itemid = li.itemid
  WHERE
    LOWER(li.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
  GROUP BY
    le.subject_id,
    le.hadm_id
),
trop_values AS (
  SELECT
    ft.subject_id,
    ft.hadm_id,
    le.valuenum,
    le.ref_range_upper
  FROM
    first_troponin ft
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON ft.subject_id = le.subject_id
      AND ft.hadm_id    = le.hadm_id
      AND ft.first_trop_time = le.charttime
)
SELECT
  CASE
    WHEN tv.valuenum <= tv.ref_range_upper THEN 'normal'
    WHEN tv.valuenum <= 2 * tv.ref_range_upper THEN 'borderline'
    ELSE 'elevated'
  END AS troponin_category,
  COUNT(1) AS n_admissions,
  ROUND(100.0 * COUNT(1) / SUM(COUNT(1)) OVER (), 1) AS pct_of_cohort,
  SUM(ca.hospital_expire_flag) AS n_deaths,
  ROUND(100.0 * SUM(ca.hospital_expire_flag) / COUNT(1), 1) AS mortality_rate_pct
FROM
  chestpain_admissions ca
  JOIN trop_values tv
    ON ca.subject_id = tv.subject_id
    AND ca.hadm_id    = tv.hadm_id
GROUP BY
  troponin_category
ORDER BY
  troponin_category;