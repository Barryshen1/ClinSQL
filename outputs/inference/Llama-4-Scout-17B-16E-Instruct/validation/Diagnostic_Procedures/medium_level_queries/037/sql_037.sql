WITH 
  -- Identify patients and classify AMI
  patients_ami AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      p.anchor_age,
      p.gender,
      CASE 
        WHEN a.admission_type = 'elective' THEN 'secondary'
        ELSE 'primary'
      END AS ami_type,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M'
      AND p.anchor_age BETWEEN 43 AND 53
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE 
          d.hadm_id = a.hadm_id
          AND d.icd_code LIKE '410%'
      )
  ),
  
  -- Count radiography/CTs per admission
  radiography_cts AS (
    SELECT 
      hadm_id,
      COUNT(*) AS radiography_ct_count
    FROM 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    WHERE 
      p.icd_code LIKE '87%'  -- Radiography
      OR p.icd_code LIKE '92%'  -- CT Scan
    GROUP BY 
      hadm_id
  )

-- Calculate median and IQR of radiography/CTs by LOS and AMI type
SELECT 
  ami_type,
  los_category,
  APPROX_QUANTILES(radiography_ct_count, 0.5)[OFFSET(0)] AS median,
  APPROX_QUANTILES(radiography_ct_count, 0.25)[OFFSET(0)] AS q1,
  APPROX_QUANTILES(radiography_ct_count, 0.75)[OFFSET(0)] AS q3
FROM 
  (
    SELECT 
      pa.ami_type,
      CASE 
        WHEN pa.los BETWEEN 1 AND 3 THEN '1-3 days'
        WHEN pa.los BETWEEN 4 AND 7 THEN '4-7 days'
        ELSE 'others'
      END AS los_category,
      COALESCE(rc.radiography_ct_count, 0) AS radiography_ct_count
    FROM 
      patients_ami pa
    LEFT JOIN 
      radiography_cts rc
    ON 
      pa.hadm_id = rc.hadm_id
  ) AS subquery
GROUP BY 
  ami_type,
  los_category
ORDER BY 
  ami_type,
  los_category;