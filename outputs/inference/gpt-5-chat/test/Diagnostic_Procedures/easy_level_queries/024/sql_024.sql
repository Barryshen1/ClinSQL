WITH proc_counts AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    COUNT(DISTINCT pr.icd_code) AS distinct_coronary_proc_ct
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pr.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND (
      (pr.icd_version = 9 AND (
          pr.icd_code IN ('3721','3722','3723')
          OR pr.icd_code LIKE '360%'
      ))
      OR
      (pr.icd_version = 10 AND (
          pr.icd_code LIKE '027%'   -- Dilation of coronary arteries (PCI)
          OR pr.icd_code LIKE 'B211%' -- Angiography of coronary arteries
          OR pr.icd_code LIKE 'B215%' -- Angiography via different approach
      ))
    )
  GROUP BY pr.subject_id, pr.hadm_id
)
SELECT
  PERCENTILE_CONT(distinct_coronary_proc_ct, 0.75) OVER() AS pct75_procedures
FROM proc_counts;