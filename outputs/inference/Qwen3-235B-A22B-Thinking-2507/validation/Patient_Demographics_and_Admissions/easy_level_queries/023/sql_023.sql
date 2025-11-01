WITH pci_procedures AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.chartdate
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON p.subject_id = pat.subject_id
  WHERE p.icd_version = 10
    AND p.icd_code IN (
      '021009D', '021009G', '021009Z', '021039D', '021039G', '021039Z',
      '021209D', '021209G', '021209Z', '021239D', '021239G', '021239Z',
      '021409D', '021409G', '021409Z', '021439D', '021439G', '021439Z',
      '021509D', '021509G', '021509Z', '021539D', '021539G', '021539Z'
    )
    AND pat.gender = 'M'
    AND (
      EXTRACT(YEAR FROM p.chartdate) - (pat.anchor_year - pat.anchor_age)
    ) BETWEEN 68 AND 78
),
qualifying_stays AS (
  SELECT 
    i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN pci_procedures p
    ON i.hadm_id = p.hadm_id
)
SELECT 
  APPROX_QUANTILES(los, 1000)[OFFSET(500)] AS median_los_days
FROM qualifying_stays;