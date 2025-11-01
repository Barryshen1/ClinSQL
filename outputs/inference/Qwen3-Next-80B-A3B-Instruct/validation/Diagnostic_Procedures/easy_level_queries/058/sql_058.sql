WITH mechanical_circulatory_support_procedures AS (
  -- ICD procedures from HOSP module
  SELECT DISTINCT p.hadm_id, d.long_title AS procedure_label
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  WHERE pt.gender = 'F'
    AND pt.anchor_age BETWEEN 86 AND 96
    AND (
      LOWER(d.long_title) LIKE '%intra-aortic balloon%'
      OR LOWER(d.long_title) LIKE '%ventricular assist%'
      OR LOWER(d.long_title) LIKE '%extracorporeal membrane oxygenation%'
      OR LOWER(d.long_title) LIKE '%mechanical circulatory support%'
    )
  
  UNION ALL
  
  -- ICU procedure events
  SELECT DISTINCT pe.hadm_id, di.label AS procedure_label
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON pe.subject_id = pt.subject_id
  WHERE pt.gender = 'F'
    AND pt.anchor_age BETWEEN 86 AND 96
    AND LOWER(di.label) IN (
      'ecmo',
      'iabp',
      'lvad',
      'rvad',
      'vad',
      'mechanical circulatory support'
    )
),

procedures_per_hadm AS (
  SELECT hadm_id, COUNT(DISTINCT procedure_label) AS num_procedures
  FROM mechanical_circulatory_support_procedures
  GROUP BY hadm_id
)

SELECT 
  PERCENTILE_CONT(num_procedures, 0.25) OVER () AS q1,
  PERCENTILE_CONT(num_procedures, 0.75) OVER () AS q3,
  PERCENTILE_CONT(num_procedures, 0.75) OVER () - PERCENTILE_CONT(num_procedures, 0.25) OVER () AS iqr
FROM procedures_per_hadm
LIMIT 1;