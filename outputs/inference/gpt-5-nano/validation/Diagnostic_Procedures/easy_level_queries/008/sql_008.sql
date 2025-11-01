WITH eligible AS (
  -- Female patients aged 88-98 (using anchor_age from hosp.patients)
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
),
counts AS (
  -- Per-patient count of distinct echocardiography procedures from ICU procedureevents
  SELECT e.subject_id,
         COUNT(DISTINCT ce.starttime) AS echo_proc_count
  FROM eligible e
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS ce
    ON ce.subject_id = e.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON di.itemid = ce.itemid
   AND (LOWER(di.label) LIKE '%echo%' OR LOWER(di.label) LIKE '%echocardiography%')
  GROUP BY e.subject_id
)
-- Compute the 25th percentile across all eligible patients (including zeros)
SELECT q[OFFSET(1)] AS percentile_25
FROM (
  SELECT APPROX_QUANTILES(echo_proc_count, 4) AS q
  FROM counts
);