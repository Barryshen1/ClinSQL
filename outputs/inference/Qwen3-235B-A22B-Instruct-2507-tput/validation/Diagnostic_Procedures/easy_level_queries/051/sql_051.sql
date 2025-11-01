WITH ecg_telemetry_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE LOWER(label) LIKE '%ecg%'
     OR LOWER(label) LIKE '%telemetry%'
),
patient_procedure_counts AS (
  SELECT
    p.subject_id,
    COUNT(*) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_icu`.procedureevents p
  INNER JOIN ecg_telemetry_items e ON p.itemid = e.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients pat ON p.subject_id = pat.subject_id
  -- Compute age at procedure starttime
  CROSS JOIN UNNEST([EXTRACT(YEAR FROM p.starttime)]) AS proc_year
  WHERE pat.gender = 'M'
    AND (proc_year - (pat.anchor_year - pat.anchor_age)) BETWEEN 41 AND 51
  GROUP BY p.subject_id
)
SELECT
  PERCENTILE_DISC(procedure_count, 0.75) OVER () AS percentile_75
FROM patient_procedure_counts
LIMIT 1;