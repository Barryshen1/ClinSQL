WITH target_admissions AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 73 AND 83
),
devices_per_adm AS (
  SELECT ta.hadm_id,
         COUNT(DISTINCT
           CASE
             WHEN LOWER(dip.long_title) LIKE '%ecmo%' OR LOWER(dip.long_title) LIKE '%extracorporeal membrane oxygenation%' THEN 'ECMO'
             WHEN LOWER(dip.long_title) LIKE '%iabp%' OR LOWER(dip.long_title) LIKE '%intra-aortic balloon%' THEN 'IABP'
             WHEN LOWER(dip.long_title) LIKE '%lvad%' OR LOWER(dip.long_title) LIKE '%ventricular assist%' OR LOWER(dip.long_title) LIKE '%left ventricular assist%' THEN 'LVAD'
             WHEN LOWER(dip.long_title) LIKE '%cardiopulmonary bypass%' OR LOWER(dip.long_title) LIKE '%cpb%' THEN 'CPB'
             ELSE NULL
           END
         ) AS device_count
  FROM target_admissions ta
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pci
        ON ta.hadm_id = pci.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dip
        ON pci.icd_code = dip.icd_code AND pci.icd_version = dip.icd_version
  GROUP BY ta.hadm_id
),
median_calc AS (
  SELECT
    device_count,
    ROW_NUMBER() OVER (ORDER BY device_count) AS rn,
    COUNT(*) OVER () AS total_rows
  FROM devices_per_adm
)
SELECT AVG(device_count) AS median_mechanical_circulatory_support_devices_per_hospitalization
FROM median_calc
WHERE rn IN (CAST(FLOOR((total_rows + 1)/2) AS INT64),
             CAST(CEIL((total_rows + 1)/2) AS INT64));