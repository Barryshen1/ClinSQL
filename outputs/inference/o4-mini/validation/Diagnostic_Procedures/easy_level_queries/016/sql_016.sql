WITH eligible_admissions AS (
  SELECT
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
),
procedure_counts AS (
  SELECT
    ea.hadm_id,
    COALESCE(COUNT(DISTINCT pe.itemid), 0) AS proc_count
  FROM
    eligible_admissions ea
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON ea.hadm_id = icu.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      ON icu.stay_id = pe.stay_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON pe.itemid = di.itemid
  WHERE
    -- filter for ECG or telemetry procedures by label
    LOWER(di.label) LIKE '%ecg%'
    OR LOWER(di.label) LIKE '%telemetry%'
  GROUP BY
    ea.hadm_id
),
percentiles AS (
  SELECT
    APPROX_QUANTILES(proc_count, 100) AS quantiles
  FROM
    procedure_counts
)
SELECT
  quantiles[OFFSET(75)] AS p75_ecg_telemetry_per_hospitalization
FROM
  percentiles;