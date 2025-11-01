WITH PatientDiagnosis AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    d.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 40 AND 50
    AND d.icd_code IN ('E11', 'E10', 'E13', 'E14', 'I10', 'I11', 'I13', 'I50') -- Diabetes codes (E11, E10, E13, E14) and Heart Failure codes (I10, I11, I13, I50)
  GROUP BY
    p.subject_id
), MedicationEvents AS (
  SELECT
    p.subject_id,
    e.charttime,
    e.medication,
    e.event_txt
  FROM PatientDiagnosis AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.emar` AS e
    ON p.subject_id = e.subject_id
), MedicationDetails AS (
  SELECT
    me.subject_id,
    me.charttime,
    me.medication,
    me.event_txt,
    md.administration_type,
    md.dose_given,
    md.dose_given_unit,
    md.route
  FROM MedicationEvents AS me
  JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` AS md
    ON me.subject_id = md.subject_id AND me.emar_id = md.emar_id AND me.emar_seq = md.emar_seq
), MedicationCategories AS (
  SELECT
    md.subject_id,
    md.charttime,
    md.medication,
    md.event_txt,
    md.administration_type,
    md.dose_given,
    md.dose_given_unit,
    md.route,
    CASE
      WHEN LOWER(md.medication) LIKE '%metformin%' OR LOWER(md.medication) LIKE '%glipizide%' OR LOWER(md.medication) LIKE '%insulin%' THEN 'antidiabetic'
      WHEN LOWER(md.medication) LIKE '%metoprolol%' OR LOWER(md.medication) LIKE '%atenolol%' OR LOWER(md.medication) LIKE '%carvedilol%' THEN 'beta-blocker'
      WHEN LOWER(md.medication) LIKE '%lisinopril%' OR LOWER(md.medication) LIKE '%enalapril%' OR LOWER(md.medication) LIKE '%losartan%' OR LOWER(md.medication) LIKE '%valsartan%' OR LOWER(md.medication) LIKE '%sacubitril%' THEN 'ACEi/ARB/ARNI'
      WHEN LOWER(md.medication) LIKE '%furosemide%' OR LOWER(md.medication) LIKE '%bumetanide%' OR LOWER(md.medication) LIKE '%torsemide%' THEN 'loop diuretic'
      ELSE 'other'
    END AS medication_category
)
SELECT
  subject_id,
  medication_category,
  charttime
FROM MedicationCategories
WHERE
  medication_category IN ('antidiabetic', 'beta-blocker', 'ACEi/ARB/ARNI', 'loop diuretic');