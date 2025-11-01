WITH mcs_procedures AS (
  SELECT 
    subject_id,
    stay_id,
    itemid
  FROM 
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON 
    pe.itemid = di.itemid
  WHERE 
    pe.itemid IN (220546, 225463, 228369)  -- IABP, Impella, VAD
    AND pe.starttime IS NOT NULL
),
patient_mcs_counts AS (
  SELECT 
    p.subject_id,
    COUNT(DISTINCT mcs.itemid) AS distinct_mcs_count
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON 
    p.subject_id = icu.subject_id
  LEFT JOIN 
    mcs_procedures mcs
  ON 
    icu.stay_id = mcs.stay_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
  GROUP BY 
    p.subject_id
)
SELECT 
  PERCENTILE_CONT(distinct_mcs_count, 0.25) AS p25_distinct_mcs_per_patient
FROM 
  patient_mcs_counts;