WITH patient_mcs_procedures AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT pe.itemid) AS distinct_mcs_procedures
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON p.subject_id = pe.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
    AND REGEXP_CONTAINS(di.label, r'ECMO|IABP|VAD|Impella|CentriMag')
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 56 AND 66
  GROUP BY p.subject_id
)
SELECT
  STDDEV_SAMP(distinct_mcs_procedures) AS sd_distinct_mcs_procedures
FROM patient_mcs_procedures;