WITH mc_support_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%ECMO%'
     OR label LIKE '%IABP%'
     OR label LIKE '%VAD%'
     OR label LIKE '%Impella%'
     OR label LIKE '%heart assist%'
     OR label LIKE '%extracorporeal membrane oxygenation%'
),

female_patients_hadm AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 96
),

procedure_counts AS (
  SELECT
    p.hadm_id,
    COUNT(DISTINCT pe.itemid) AS num_procedures
  FROM female_patients_hadm p
  LEFT JOIN (
    SELECT pe.*
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    JOIN mc_support_items msi ON pe.itemid = msi.itemid
  ) pe ON p.hadm_id = pe.hadm_id
  GROUP BY p.hadm_id
)

SELECT
  PERCENTILE_CONT(num_procedures, 0.75) OVER () - PERCENTILE_CONT(num_procedures, 0.25) OVER () AS iqr
FROM procedure_counts
LIMIT 1;