WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%diabetes%'
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%heart failure%'
        AND LOWER(dd.long_title) LIKE '%acute%'
    )
),

insulin_admins AS (
  SELECT
    c.stay_id,
    CASE
      WHEN LOWER(i.ordercategoryname) LIKE '%basal-bolus%' THEN 'Basal-Bolus'
      WHEN LOWER(i.ordercategoryname) LIKE '%bolus%' THEN 'Bolus'
      WHEN LOWER(i.ordercategoryname) LIKE '%basal%' THEN 'Basal'
      WHEN LOWER(i.ordercategoryname) LIKE '%sliding scale%' THEN 'Sliding Scale'
      ELSE 'Other'
    END AS insulin_type,
    CASE
      WHEN i.starttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR) THEN 'First24h'
      WHEN i.starttime BETWEEN DATETIME_SUB(c.outtime, INTERVAL 12 HOUR) AND c.outtime THEN 'Final12h'
      ELSE NULL
    END AS time_window
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.inputevents` i
    ON c.stay_id = i.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` d
    ON i.itemid = d.itemid
  WHERE
    LOWER(d.label) LIKE '%insulin%'
    AND i.ordercategoryname IS NOT NULL
    AND i.starttime IS NOT NULL
),

window_counts AS (
  SELECT
    time_window,
    insulin_type,
    COUNT(*) AS count
  FROM
    insulin_admins
  WHERE
    time_window IN ('First24h', 'Final12h')
    AND insulin_type != 'Other'
  GROUP BY
    time_window,
    insulin_type
),

window_totals AS (
  SELECT
    time_window,
    COUNT(*) AS total
  FROM
    insulin_admins
  WHERE
    time_window IN ('First24h', 'Final12h')
    AND insulin_type != 'Other'
  GROUP BY
    time_window
),

pct_by_window AS (
  SELECT
    wc.time_window,
    wc.insulin_type,
    wc.count,
    wt.total,
    ROUND(100 * wc.count / wt.total, 2) AS percentage
  FROM
    window_counts wc
  JOIN
    window_totals wt
    ON wc.time_window = wt.time_window
),

pivot AS (
  SELECT
    insulin_type,
    MAX(CASE WHEN time_window = 'First24h' THEN percentage ELSE 0 END) AS first24h_pct,
    MAX(CASE WHEN time_window = 'Final12h' THEN percentage ELSE 0 END) AS final12h_pct
  FROM
    pct_by_window
  GROUP BY
    insulin_type
)

SELECT
  insulin_type,
  first24h_pct,
  final12h_pct,
  ROUND(final12h_pct - first24h_pct, 2) AS pct_point_change
FROM
  pivot
ORDER BY
  insulin_type;