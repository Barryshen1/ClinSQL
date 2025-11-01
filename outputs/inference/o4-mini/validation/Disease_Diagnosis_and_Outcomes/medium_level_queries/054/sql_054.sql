WITH postop_adm AS (
  -- 1) Identify 44-year-old men with postoperative complication
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dict
      ON d.icd_code = dict.icd_code
     AND d.icd_version = dict.icd_version
  WHERE
    p.anchor_age = 44
    AND p.gender = 'M'
    AND LOWER(dict.long_title) LIKE '%postoperative complication%'
),
icu_flags AS (
  -- 2) Flag ICU vs non-ICU by hadm_id
  SELECT
    pa.*,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
        WHERE icu.hadm_id = pa.hadm_id
      ) THEN 'ICU'
      ELSE 'Non-ICU'
    END AS icu_flag
  FROM postop_adm pa
),
los_cat AS (
  -- 3) Bucket LOS
  SELECT
    *,
    CASE
      WHEN los_days <= 3 THEN '≤3'
      WHEN los_days BETWEEN 4 AND 6 THEN '4–6'
      WHEN los_days BETWEEN 7 AND 10 THEN '7–10'
      ELSE '>10'
    END AS los_bucket
  FROM icu_flags
),
charlson_cat AS (
  -- 4) Placeholder Charlson (no table available), assign all to 'Unknown'
  SELECT
    l.*,
    NULL AS charlson_score,
    'Unknown' AS charlson_bucket
  FROM los_cat l
),
vent_events AS (
  -- 5a) Flag mechanical ventilation
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE ce.itemid IN (
    SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE LOWER(label) LIKE '%ventilator%'
  )
),
vaso_events AS (
  -- 5b) Flag vasopressors (example using inputevents.ordercategoryname)
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  WHERE LOWER(ie.ordercategoryname) IN ('vasopressor','vasopressors')
    OR LOWER(ie.ordercomponenttypedescription) IN ('norepinephrine','epinephrine','phenylephrine','vasopressin')
),
rrt_events AS (
  -- 5c) Flag RRT via dialysis procedureevents
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE LOWER(value) LIKE '%hemodialysis%'
),
final AS (
  -- 6) Aggregate outcomes
  SELECT
    cc.icu_flag,
    cc.los_bucket,
    cc.charlson_bucket,
    COUNT(*) AS n_adm,
    SUM(CASE WHEN cc.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
    ROUND(100.0 * SUM(CASE WHEN cc.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_mortality,
    SUM(CASE WHEN ve.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS n_vent,
    ROUND(100.0 * SUM(CASE WHEN ve.hadm_id IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_vent,
    SUM(CASE WHEN va.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS n_vaso,
    ROUND(100.0 * SUM(CASE WHEN va.hadm_id IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_vaso,
    SUM(CASE WHEN re.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS n_rrt,
    ROUND(100.0 * SUM(CASE WHEN re.hadm_id IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_rrt
  FROM charlson_cat cc
  LEFT JOIN vent_events ve ON cc.hadm_id = ve.hadm_id
  LEFT JOIN vaso_events va ON cc.hadm_id = va.hadm_id
  LEFT JOIN rrt_events re ON cc.hadm_id = re.hadm_id
  GROUP BY 1,2,3
),
with_ref AS (
  -- 7) Compute differences vs the LOS ≤3 referent
  SELECT
    *,
    FIRST_VALUE(pct_mortality) OVER (
      PARTITION BY icu_flag, charlson_bucket
      ORDER BY CASE WHEN los_bucket = '≤3' THEN 0 ELSE 1 END
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS ref_mortality
  FROM final
)
SELECT
  icu_flag,
  charlson_bucket,
  los_bucket,
  n_adm,
  pct_mortality,
  ROUND(pct_mortality - ref_mortality, 1) AS abs_diff_vs_le_3,
  ROUND(
    CASE WHEN ref_mortality > 0
      THEN 100.0 * (pct_mortality - ref_mortality) / ref_mortality
      ELSE NULL
    END, 1
  ) AS rel_diff_vs_le_3_pct,
  pct_vent,
  pct_vaso,
  pct_rrt
FROM with_ref
ORDER BY
  icu_flag,
  charlson_bucket,
  CASE los_bucket
    WHEN '≤3' THEN 1
    WHEN '4–6' THEN 2
    WHEN '7–10' THEN 3
    ELSE 4
  END;