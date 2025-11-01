WITH mcs_procs AS (
  SELECT
    pi.subject_id,
    pi.hadm_id,
    pi.icd_code,
    pi.icd_version,
    d.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d
    ON pi.icd_code = d.icd_code
   AND pi.icd_version = d.icd_version
  WHERE LOWER(d.long_title) IS NOT NULL
    AND REGEXP_CONTAINS(
      LOWER(d.long_title),
      r'(assist|ventricular assist|ventricular-assist|intra-?aortic|balloon pump|balloon-pump|ecmo|extracorporeal|artificial heart|circulatory support|cardiac assist|ventricular assist device|left ventricular assist|lvad|vad)'
    )
),
per_patient_counts AS (
  -- count distinct procedure codes (include version) per patient
  SELECT
    subject_id,
    COUNT(DISTINCT CONCAT(CAST(icd_version AS STRING), '::', icd_code)) AS num_distinct_mcs
  FROM mcs_procs
  GROUP BY subject_id
)
SELECT
  MIN(ppc.num_distinct_mcs) AS min_distinct_mcs_among_females_40_50_with_MCS
FROM per_patient_counts AS ppc
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON ppc.subject_id = pat.subject_id
WHERE pat.anchor_age BETWEEN 40 AND 50
  AND UPPER(pat.gender) = 'F';