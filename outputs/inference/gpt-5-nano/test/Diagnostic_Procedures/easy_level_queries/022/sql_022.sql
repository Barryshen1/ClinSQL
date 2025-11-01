WITH eligible_hadm AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 82 AND 92
),
pacemaker_implants AS (
  SELECT pc.hadm_id, pc.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pc
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS di
    ON pc.icd_code = di.icd_code
   AND pc.icd_version = di.icd_version
  WHERE LOWER(di.long_title) LIKE '%pacemaker%'
     OR LOWER(di.long_title) LIKE '%implant%'
     OR LOWER(di.long_title) LIKE '%defibrillator%'
)
SELECT MIN(num_implantations) AS min_distinct_pacemaker_or_icd_implantations
FROM (
  SELECT e.hadm_id,
         COUNT(DISTINCT pi.icd_code) AS num_implantations
  FROM eligible_hadm AS e
  LEFT JOIN pacemaker_implants AS pi
    ON pi.hadm_id = e.hadm_id
  GROUP BY e.hadm_id
) AS t;