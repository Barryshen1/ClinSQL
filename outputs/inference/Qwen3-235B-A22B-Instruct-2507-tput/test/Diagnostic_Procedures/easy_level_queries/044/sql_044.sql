WITH mcs_items AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%balloon pump%'
     OR LOWER(label) LIKE '%impella%'
),
patient_mcs_counts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT mi.itemid) AS distinct_mcs_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON p.subject_id = pe.subject_id
  INNER JOIN mcs_items mi
    ON pe.itemid = mi.itemid
  -- Calculate age at procedure starttime
  , UNNEST([EXTRACT(YEAR FROM pe.starttime)]) AS proc_year
  WHERE p.gender = 'M'
    AND (p.anchor_age + (proc_year - p.anchor_year)) BETWEEN 56 AND 66
  GROUP BY p.subject_id
)
SELECT
  STDDEV(distinct_mcs_count) AS sd_distinct_mcs_procedures_per_patient
FROM patient_mcs_counts;