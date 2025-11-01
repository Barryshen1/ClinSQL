WITH 
  -- Identify MCS devices (for simplicity, let's assume we have a list of itemids)
  mcs_itemids AS (
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_icu.d_items` 
    WHERE label IN ('IABP', 'ECMO', 'VAD')  -- Example MCS devices
  ),
  
  -- Find MCS events
  mcs_events AS (
    SELECT 
      ie.subject_id,
      ie.hadm_id,
      ie.itemid
    FROM 
      `physionet-data.mimiciv_3_1_icu.inputevents` ie
    WHERE 
      ie.itemid IN (SELECT itemid FROM mcs_itemids)
    UNION DISTINCT
    SELECT 
      pe.subject_id,
      pe.hadm_id,
      pe.itemid
    FROM 
      `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    WHERE 
      pe.itemid IN (SELECT itemid FROM mcs_itemids)
  ),
  
  -- Filter patients of interest
  patients_of_interest AS (
    SELECT 
      p.subject_id,
      p.anchor_age
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE 
      p.gender = 'M' AND 
      p.anchor_age BETWEEN 73 AND 83
  ),
  
  -- Count distinct MCS devices per hospitalization
  mcs_counts AS (
    SELECT 
      a.hadm_id,
      COUNT(DISTINCT mcs.itemid) AS mcs_count
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      patients_of_interest poi ON a.subject_id = poi.subject_id
    JOIN 
      mcs_events mcs ON a.hadm_id = mcs.hadm_id AND a.subject_id = mcs.subject_id
    GROUP BY 
      a.hadm_id
  )

-- Calculate median MCS count
SELECT 
  APPROX_QUANTILES(mcs_count, 100)[51] AS median_mcs_count
FROM 
  mcs_counts;