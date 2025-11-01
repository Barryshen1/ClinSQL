WITH
  -- SBP itemids from d_items (e.g., "Arterial Blood Pressure systolic", "NIBP Systolic", etc.)
  sbp_itemids AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE LOWER(label) LIKE '%systolic%'
  ),

  -- d_items that explicitly mention high flow / HFNC (if present)
  hfnc_itemids AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE LOWER(label) LIKE '%high flow%'
       OR LOWER(label) LIKE '%high-flow%'
       OR LOWER(label) LIKE '%hfnc%'
  ),

  -- HFNC mentions from chartevents (either via item label or free-text value)
  hfnc_chartevents AS (
    SELECT DISTINCT stay_id
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
    WHERE ce.stay_id IS NOT NULL
      AND (
        di.itemid IN (SELECT itemid FROM hfnc_itemids)
        OR LOWER(COALESCE(CAST(di.label AS STRING), '')) LIKE '%high flow%'
        OR LOWER(COALESCE(CAST(ce.value AS STRING), '')) LIKE '%high flow%'
        OR LOWER(COALESCE(CAST(ce.value AS STRING), '')) LIKE '%hfnc%'
        OR LOWER(COALESCE(CAST(ce.value AS STRING), '')) LIKE '%high-flow%'
      )
  ),

  -- HFNC mentions from procedureevents (value text or item label)
  hfnc_procedureevents AS (
    SELECT DISTINCT stay_id
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON pe.itemid = di.itemid
    WHERE pe.stay_id IS NOT NULL
      AND (
        di.itemid IN (SELECT itemid FROM hfnc_itemids)
        OR LOWER(COALESCE(CAST(di.label AS STRING), '')) LIKE '%high flow%'
        OR LOWER(COALESCE(CAST(pe.value AS STRING), '')) LIKE '%high flow%'
        OR LOWER(COALESCE(CAST(pe.value AS STRING), '')) LIKE '%hfnc%'
        OR LOWER(COALESCE(CAST(pe.value AS STRING), '')) LIKE '%high-flow%'
      )
  ),

  -- HFNC mentions from inputevents (item label or descriptive fields)
  hfnc_inputevents AS (
    SELECT DISTINCT stay_id
    FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ie.itemid = di.itemid
    WHERE ie.stay_id IS NOT NULL
      AND (
        di.itemid IN (SELECT itemid FROM hfnc_itemids)
        OR LOWER(COALESCE(CAST(di.label AS STRING), '')) LIKE '%high flow%'
        OR LOWER(COALESCE(CAST(ie.ordercategorydescription AS STRING), '')) LIKE '%high flow%'
        OR LOWER(COALESCE(CAST(ie.secondaryordercategoryname AS STRING), '')) LIKE '%high flow%'
        OR LOWER(COALESCE(CAST(ie.ordercomponenttypedescription AS STRING), '')) LIKE '%high flow%'
        OR LOWER(COALESCE(CAST(di.label AS STRING), '')) LIKE '%hfnc%'
        OR LOWER(COALESCE(CAST(ie.ordercategorydescription AS STRING), '')) LIKE '%hfnc%'
      )
  ),

  -- Combined HFNC stay list (union from multiple sources)
  hfnc_stays AS (
    SELECT stay_id FROM hfnc_chartevents
    UNION DISTINCT
    SELECT stay_id FROM hfnc_procedureevents
    UNION DISTINCT
    SELECT stay_id FROM hfnc_inputevents
  ),

  -- Per-stay mean systolic blood pressure (use numeric valuenum, restrict to physiologic range)
  sbp_per_stay AS (
    SELECT
      ce.stay_id,
      AVG(ce.valuenum) AS mean_sbp
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    WHERE ce.stay_id IS NOT NULL
      AND ce.itemid IN (SELECT itemid FROM sbp_itemids)
      AND ce.valuenum IS NOT NULL
      AND ce.valuenum BETWEEN 20 AND 300
    GROUP BY ce.stay_id
  )

-- Final aggregation: among female patients age 81-91 with HFNC during ICU stay,
-- compute the minimum per-stay mean SBP.
SELECT
  MIN(s.mean_sbp) AS min_per_stay_mean_sbp_mmHg,
  COUNT(*) AS n_stays_considered
FROM sbp_per_stay s
JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
  ON s.stay_id = i.stay_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON i.subject_id = p.subject_id
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 81 AND 91
  AND s.stay_id IN (SELECT stay_id FROM hfnc_stays);