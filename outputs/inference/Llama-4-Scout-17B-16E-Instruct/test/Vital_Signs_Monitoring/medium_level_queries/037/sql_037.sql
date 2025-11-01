WITH 
  -- Define itemids for HFNC and GCS
  itemids AS (
    SELECT itemid, label
    FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE label IN ('High flow nasal cannula', 'Glasgow coma scale total')
  ),
  
  -- Select relevant patient and ICU stay data
  patients_stays AS (
    SELECT 
      p.subject_id,
      p.gender,
      p.anchor_age,
      ic.stay_id,
      ic.hadm_id,
      ic.intime,
      ic.outtime
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` ic 
        ON p.subject_id = ic.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 88 AND 98
  ),
  
  -- Select HFNC and GCS events
  events AS (
    SELECT 
      ps.subject_id,
      ps.stay_id,
      ps.hadm_id,
      ce.charttime,
      ce.itemid,
      ce.valuenum
    FROM 
      patients_stays ps
    JOIN 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce 
        ON ps.stay_id = ce.stay_id
    WHERE 
      ce.itemid IN (SELECT itemid FROM itemids)
  ),
  
  -- Identify HFNC use and calculate ICU day for GCS
  hfnc_gcs AS (
    SELECT 
      subject_id,
      stay_id,
      hadm_id,
      charttime,
      valuenum AS gcs_total
    FROM 
      events
    WHERE 
      itemid = (SELECT itemid FROM itemids WHERE label = 'Glasgow coma scale total')
      AND DATE_DIFF(charttime, 
                    (SELECT intime FROM patients_stays 
                     WHERE patients_stays.stay_id = events.stay_id), 
                    DAY) >= 2
    AND 
      subject_id IN (
        SELECT 
          subject_id
        FROM 
          events
        WHERE 
          itemid = (SELECT itemid FROM itemids WHERE label = 'High flow nasal cannula')
      )
  )

SELECT 
  APPROX_QUANTILES(gcs_total, 100)[OFFSET(50)] AS median_gcs
FROM 
  hfnc_gcs;