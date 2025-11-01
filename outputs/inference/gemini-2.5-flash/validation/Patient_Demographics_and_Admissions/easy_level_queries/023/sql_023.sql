WITH FilteredICUData AS (
  SELECT
    icu.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON icu.subject_id = p.subject_id
  JOIN
    (
      -- Subquery to identify hospital admissions where a Percutaneous Coronary Intervention (PCI) occurred
      -- Distinct hadm_id ensures each admission is counted only once for the join
      SELECT DISTINCT
        proc.hadm_id
      FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
      JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d_proc
        ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
      WHERE
        (
          LOWER(d_proc.long_title) LIKE '%coronary%' AND LOWER(d_proc.long_title) LIKE '%angioplasty%'
        )
        OR (
          LOWER(d_proc.long_title) LIKE '%coronary%' AND LOWER(d_proc.long_title) LIKE '%stent%'
        )
        OR LOWER(d_proc.long_title) LIKE '%percutaneous transluminal coronary%'
    ) AS pci_admissions
    ON icu.hadm_id = pci_admissions.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND icu.los IS NOT NULL -- Exclude NULL LOS values from median calculation
)
SELECT
  -- Calculate the exact median ICU Length of Stay (LOS) in days using ARRAY_AGG
  CASE
    WHEN COUNT(f.los) = 0 THEN NULL -- Handle case with no data
    WHEN MOD(COUNT(f.los), 2) = 1 THEN -- If count is odd, median is the middle element
      ARRAY_AGG(f.los ORDER BY f.los)[OFFSET(CAST(FLOOR(COUNT(f.los)/2) AS INT))]
    ELSE -- If count is even, median is the average of the two middle elements
      (ARRAY_AGG(f.los ORDER BY f.los)[OFFSET(CAST(FLOOR(COUNT(f.los)/2) - 1 AS INT))] +
       ARRAY_AGG(f.los ORDER BY f.los)[OFFSET(CAST(FLOOR(COUNT(f.los)/2) AS INT))]) / 2.0
  END AS median_icu_los_days
FROM FilteredICUData AS f;