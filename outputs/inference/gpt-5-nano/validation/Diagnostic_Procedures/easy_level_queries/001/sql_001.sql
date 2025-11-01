WITH eligible_hadm AS (
  -- Select hospitalizations for which the patient is a male aged 63-73 at admission
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 63 AND 73
    AND UPPER(p.gender) = 'M'
),
cardiac_procedure_counts AS (
  SELECT eh.hadm_id,
         COUNT(DISTINCT CASE
           WHEN dip.long_title IS NOT NULL
            AND (
              LOWER(dip.long_title) LIKE '%cardiac%' OR
              LOWER(dip.long_title) LIKE '%coronary%' OR
              LOWER(dip.long_title) LIKE '%heart%' OR
              LOWER(dip.long_title) LIKE '%pacemaker%' OR
              LOWER(dip.long_title) LIKE '%defibrillator%' OR
              LOWER(dip.long_title) LIKE '%valve%' OR
              LOWER(dip.long_title) LIKE '%angioplast%' OR
              LOWER(dip.long_title) LIKE '%stent%' OR
              LOWER(dip.long_title) LIKE '%bypass%'
            )
           THEN pi.icd_code
           ELSE NULL
         END) AS card_count
  FROM eligible_hadm eh
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
    ON pi.hadm_id = eh.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dip
    ON dip.icd_code = pi.icd_code
  GROUP BY eh.hadm_id
)
SELECT PERCENTILE_CONT(card_count, 0.75) OVER () AS percentile_75_cardiac_procedures_per_hospitalization
FROM cardiac_procedure_counts
LIMIT 1;