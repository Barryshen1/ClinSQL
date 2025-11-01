WITH eligible_admissions AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE LOWER(p.gender) IN ('m', 'male')
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
      JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
        ON pe.itemid = di.itemid
      WHERE pe.hadm_id = a.hadm_id
        AND LOWER(di.label) LIKE '%dialysis%'
    )
),
los_per_admission AS (
  SELECT a.hadm_id,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN eligible_admissions AS e
    ON a.hadm_id = e.hadm_id
)
SELECT STDDEV_SAMP(los_days) AS sd_los_days
FROM los_per_admission;