WITH 
  -- Identify patients of interest
  patients_of_interest AS (
    SELECT 
      a.subject_id, 
      a.hadm_id, 
      ic.stay_id,
      p.anchor_age,
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` ic 
        ON a.hadm_id = ic.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F' 
      AND p.anchor_age BETWEEN 84 AND 94
      AND EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
          ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
        WHERE 
          d.hadm_id = a.hadm_id 
          AND dd.long_title LIKE '%Acute respiratory distress syndrome%'
      )
  ),
  
  -- Calculate diagnostic intensity (distinct procedures in first 24h)
  diagnostic_intensity AS (
    SELECT 
      poi.hadm_id,
      COUNT(DISTINCT pe.itemid) AS num_procedures
    FROM 
      patients_of_interest poi
    JOIN 
      `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
        ON poi.stay_id = pe.stay_id
    WHERE 
      pe.starttime BETWEEN poi.ic.intime AND TIMESTAMP_ADD(poi.ic.intime, INTERVAL 1 DAY)
    GROUP BY 
      poi.hadm_id
  ),
  
  -- Calculate hospital LOS and mortality
  hospital_outcomes AS (
    SELECT 
      poi.hadm_id,
      a.hospital_expire_flag,
      DATE_DIFF(a.dischtime, a.admittime) AS los
    FROM 
      patients_of_interest poi
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON poi.hadm_id = a.hadm_id
  ),
  
  -- General ICU population for comparison
  general_icu AS (
    SELECT 
      ic.hadm_id,
      COUNT(DISTINCT pe.itemid) AS num_procedures_general,
      a.hospital_expire_flag,
      DATE_DIFF(a.dischtime, a.admittime) AS los_general
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` ic
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON ic.hadm_id = a.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
        ON ic.stay_id = pe.stay_id
    GROUP BY 
      ic.hadm_id, a.hospital_expire_flag, DATE_DIFF(a.dischtime, a.admittime)
  )

SELECT 
  -- Percentiles of diagnostic intensity
  APPROX_QUANTILES(di.num_procedures, 1000)[OFFSET(250)] AS p25,
  APPROX_QUANTILES(di.num_procedures, 1000)[OFFSET(750)] AS p75,
  APPROX_QUANTILES(di.num_procedures, 1000)[OFFSET(950)] AS p95,
  -- Average hospital LOS
  AVG(ho.los) AS avg_los,
  -- Hospital mortality
  AVG(ho.hospital_expire_flag) AS hospital_mortality,
  -- General ICU population comparison
  AVG(general_icu.num_procedures_general) AS avg_num_procedures_general,
  AVG(general_icu.los_general) AS avg_los_general,
  AVG(general_icu.hospital_expire_flag) AS hospital_mortality_general
FROM 
  diagnostic_intensity di
JOIN 
  hospital_outcomes ho ON di.hadm_id = ho.hadm_id
CROSS JOIN 
  (SELECT AVG(num_procedures_general) AS num_procedures_general,
          AVG(los_general) AS los_general,
          AVG(hospital_expire_flag) AS hospital_expire_flag
   FROM general_icu) AS general_icu;