WITH
  -- Identify Troponin T measurement itemids
  troponin_items AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE LOWER(label) LIKE '%troponin t%'
  ),

  -- All Troponin T events with numeric values
  initial_events AS (
    SELECT le.subject_id, le.hadm_id, le.charttime, le.valuenum
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN troponin_items ti ON le.itemid = ti.itemid
    WHERE le.valuenum IS NOT NULL
  ),

  -- Initial Troponin T per admission: earliest charttime for each (subject_id, hadm_id)
  initial_first AS (
    SELECT subject_id, hadm_id, charttime, valuenum
    FROM (
      SELECT
        subject_id,
        hadm_id,
        charttime,
        valuenum,
        ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY charttime ASC) AS rn
      FROM initial_events
    )
    WHERE rn = 1
  ),

  -- Dataset ULN: 99th percentile of all Troponin T values (using 100 quantiles)
  ulndata AS (
    SELECT quantiles[OFFSET(99)] AS uln
    FROM (
      SELECT APPROX_QUANTILES(valuenum, 100) AS quantiles
      FROM initial_events
    )
  ),

  -- Patients in the age/gender window
  patients_filter AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M'
      AND anchor_age BETWEEN 49 AND 59
  ),

  -- Final cohort: initial Troponin T per admission for those patients
  final_cohort AS (
    SELECT f.subject_id, f.hadm_id, f.charttime, f.valuenum
    FROM initial_first f
    JOIN patients_filter p ON f.subject_id = p.subject_id
  ),

  -- Eligible values: initial Troponin T values that exceed ULN
  eligible_values AS (
    SELECT fc.valuenum
    FROM final_cohort fc
    CROSS JOIN ulndata u
    WHERE fc.valuenum > u.uln
  ),

  -- 25th/50th/75th percentiles using 4-quantiles on eligible values
  quantiles4 AS (
    SELECT APPROX_QUANTILES(valuenum, 4) AS q
    FROM eligible_values
  ),

  -- Min / Max of eligible values
  minmax AS (
    SELECT MIN(valuenum) AS min_val, MAX(valuenum) AS max_val
    FROM eligible_values
  )

SELECT
  -- Cohort size: number of unique subjects in final cohort who exceed ULN
  (SELECT COUNT(DISTINCT fc.subject_id)
     FROM final_cohort fc
     JOIN patients_filter p ON fc.subject_id = p.subject_id
     CROSS JOIN ulndata u
     WHERE fc.valuenum > u.uln
  ) AS cohort_size,

  -- ULN (99th percentile)
  (SELECT uln FROM ulndata) AS uln,

  -- p25, p50, p75 from eligible values
  (SELECT q[OFFSET(1)] FROM quantiles4) AS p25,
  (SELECT q[OFFSET(2)] FROM quantiles4) AS p50,
  (SELECT q[OFFSET(3)] FROM quantiles4) AS p75,

  -- Min and Max of eligible values
  (SELECT min_val FROM minmax) AS min_val,
  (SELECT max_val FROM minmax) AS max_val;